import Foundation
import SwiftUI
import WisentDesignSystem
import WisentOnboarding

/// The identity of the journey this build can actually finish, in one place off
/// the main actor: the transport below runs on whatever executor Echo's client
/// calls it from, and the controller runs on the main actor, and both compare
/// against these exact strings.
private enum GlinaJourney {
    static let productID = "glina-desktop"
    static let journeyID = "first-use"
    static let journeyVersion = "2026-09-01.1"
    static let firstSuccessFact = "glb_asset_sculpted"
    static let evidenceRevision = "glina-desktop-first-use-2026-09-01"
    static let storageNamespace = "ai.wisent.glina.onboarding.2026-09-01.1"
    static let installationIDKey = "ai.wisent.glina.onboarding.installation-id"
    static let fallbackVersionID = UUID(uuidString: "3A7C41D6-9F2E-4B58-9C0A-6D5E11B8F204")!
    static let resourceName = "glina-desktop-first-use"
    static let tokenEnvironmentKey = "GLINA_DESKTOP_STADO_INTEGRATION_TOKEN"
}

/// Echo's transport, with Glina's identity checked before the central bundle is
/// trusted.
///
/// The control plane can serve a newer journey than this build was written
/// against. Accepting it silently would put a screen on the window whose final
/// step Glina has no way to observe — the fact name is compiled into
/// `observeSculptedAsset` — and first use would never finish. A mismatch is
/// refused here so the client falls back to the bundled definition, which this
/// build does know how to complete.
private struct GlinaJourneyTransport: JourneyTransport {
    private let base = EnvironmentJourneyTransport(
        tokenEnvironmentKey: GlinaJourney.tokenEnvironmentKey
    )

    func readBundle(productId: String, journeyId: String) async throws -> JourneyBundle {
        let bundle = try await base.readBundle(productId: productId, journeyId: journeyId)
        guard bundle.definition.journeyVersion == GlinaJourney.journeyVersion,
              bundle.definition.firstSuccessFact == GlinaJourney.firstSuccessFact
        else {
            throw JourneyClientError.invalid("Glina journey identity")
        }
        return bundle
    }

    func readState(productId: String, attemptId: UUID, subjectHash: String) async throws -> JSONValue? {
        try await base.readState(productId: productId, attemptId: attemptId, subjectHash: subjectHash)
    }

    func assignExperiment(request: JourneyAssignmentRequest) async throws -> JourneyAssignmentResponse {
        try await base.assignExperiment(request: request)
    }

    func collect(event: JourneyRuntimeEvent) async throws {
        try await base.collect(event: event)
    }
}

/// Glina's first-run walkthrough: three screens ending in a real `.glb`.
///
/// The journey is not a tour of the sidebar. Its last screen is not dismissed
/// by a button — it is finished by Glina reporting an asset it actually wrote,
/// which is why `observeSculptedAsset` is the only path to `.completed` and why
/// the overlay steps out of the way (`awaitingSculpt`) instead of closing when
/// the operator says they are ready to sculpt. An operator who quits in that
/// state is put back on the same screen next launch: progress persists on the
/// screen they reached, not on the button they pressed.
@MainActor
final class GlinaOnboarding: ObservableObject {
    private enum State: Equatable {
        case loading
        case presenting
        case awaitingSculpt
        case completed
    }

    @Published private(set) var screen: JourneyScreen?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private var state: State = .loading

    private var client: JourneyClient?
    private var hasStarted = false
    private var exposedScreenID: String?

    /// One overlay, driven by one flag, as every other Wisent desktop does it.
    var isPresented: Bool { state == .presenting }

    /// The screen whose completion is evidence rather than a click.
    var isFinalScreen: Bool { screen?.transitions.isEmpty == true }

    var stepNumber: Int? {
        switch screen?.screenId {
        case "promise": 1
        case "command_boundary": 2
        case "first_success": 3
        default: nil
        }
    }

    /// The gate: a completed journey is never presented again on its own.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isWorking = true
        defer { isWorking = false }

        do {
            let (client, progress) = try await bootstrap()
            self.client = client
            screen = await client.currentScreen
            if progress.status == .completed {
                state = .completed
                screen = nil
                try? await client.flush()
            } else {
                state = .presenting
                try await expose(using: client)
                try? await client.flush()
            }
        } catch {
            screen = nil
            errorMessage = "Glina couldn’t load its first-run walkthrough. Try again to continue."
            state = .presenting
        }
    }

    func advance() async {
        guard let client, !isFinalScreen else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            guard try await client.advance(
                evidence: [:],
                evidenceRevision: GlinaJourney.evidenceRevision
            ) != nil else { return }
            screen = await client.currentScreen
            try await expose(using: client)
        } catch {
            errorMessage = "Glina couldn’t save this step. Try again."
        }
    }

    /// The operator said they are ready to sculpt, so the overlay gets out of
    /// the way of the Sculpt screen without claiming first use is finished.
    func prepareToSculpt() {
        guard isFinalScreen else { return }
        errorMessage = nil
        state = .awaitingSculpt
    }

    /// First success, observed rather than asserted.
    ///
    /// `GlinaModel` has no opinion about onboarding; the window watches the
    /// `.glb` path Glina reported for a finished sculpt and hands it here. The
    /// path travels into the evidence revision so a second asset records a
    /// second observation instead of colliding with the first.
    func observeSculptedAsset(path: String) async {
        guard let client, state == .awaitingSculpt || state == .presenting else { return }
        do {
            let completed = try await client.complete(
                evidence: [GlinaJourney.firstSuccessFact: .boolean(true)],
                evidenceRevision: "glb-asset-sculpted:\(path)"
            )
            guard completed else { return }
            state = .completed
            screen = nil
            errorMessage = nil
            try await client.flush()
        } catch {
            return
        }
    }

    func retry() async {
        client = nil
        screen = nil
        exposedScreenID = nil
        hasStarted = false
        state = .loading
        errorMessage = nil
        await start()
    }

    /// Check Config asking for the walkthrough a second time.
    ///
    /// Finishing the journey once made it unreachable: nothing in Glina could
    /// put it back on screen, so an operator who clicked through it could never
    /// read it again. The reset goes through the same client that recorded the
    /// first viewing, so Echo sees one `onboarding_reset` followed by one
    /// `onboarding_started` — a second attempt in the funnel, not a completed
    /// journey that silently reappears. Republishing the entry screen is the
    /// whole of the presentation: the window's overlay is driven by
    /// `isPresented`, so the walkthrough returns to the window already open,
    /// which is what "again" meant. `exposedScreenID` is cleared because the
    /// replayed entry screen is a view of a new attempt, and leaving the old id
    /// there would swallow its `onboarding_step_viewed`.
    ///
    /// A session where the journey never loaded starts it here rather than
    /// refusing: a dead control is worse than a slow one. The outcome is
    /// returned instead of stored so the row that was clicked reports it.
    func replay() async -> WisentMutationOutcome {
        isWorking = true
        defer { isWorking = false }
        do {
            let client: JourneyClient
            if let started = self.client {
                client = started
            } else {
                (client, _) = try await bootstrap()
                self.client = client
                hasStarted = true
            }
            try await client.reset(evidenceRevision: GlinaJourney.evidenceRevision)
            exposedScreenID = nil
            screen = await client.currentScreen
            errorMessage = nil
            state = .presenting
            try await expose(using: client)
            try await client.flush()
            return .succeeded("Started. The walkthrough is over this window.")
        } catch {
            return .failed(Self.replayFailure(error))
        }
    }

    private func bootstrap() async throws -> (JourneyClient, JourneyProgress) {
        let client = try Self.makeClient()
        let (_, progress) = try await client.start(evidenceRevision: GlinaJourney.evidenceRevision)
        return (client, progress)
    }

    /// Off the main actor on purpose.
    ///
    /// `UserDefaults` is not `Sendable`, so handing a main-actor value to
    /// `UserDefaultsJourneyStorage` — an actor — is a data race the compiler
    /// refuses. The store is reached from here, where nothing is isolated, so
    /// there is one `UserDefaults` reference and it never crosses an isolation
    /// boundary.
    private nonisolated static func makeClient() throws -> JourneyClient {
        try JourneyClient(
            productId: GlinaJourney.productID,
            journeyId: GlinaJourney.journeyID,
            subjectHash: JourneySubject.scoped([
                GlinaJourney.productID,
                JourneyScope.device.rawValue,
                installationID(),
            ]),
            scope: .device,
            transport: GlinaJourneyTransport(),
            storage: UserDefaultsJourneyStorage(namespace: GlinaJourney.storageNamespace),
            fallback: try loadFallback()
        )
    }

    /// One `onboarding_step_viewed` per screen, not one per republish: `advance`
    /// and `replay` both re-read the current screen, and a repeat exposure would
    /// inflate the funnel's first step.
    private func expose(using client: JourneyClient) async throws {
        guard let screen, screen.screenId != exposedScreenID else { return }
        try await client.expose(evidenceRevision: GlinaJourney.evidenceRevision)
        exposedScreenID = screen.screenId
    }

    /// A stable per-machine subject, so quitting Glina does not restart the
    /// walkthrough and two machines are two subjects.
    private nonisolated static func installationID() -> String {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: GlinaJourney.installationIDKey),
           UUID(uuidString: saved) != nil {
            return saved
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: GlinaJourney.installationIDKey)
        return created
    }

    /// The bundled definition, checked against the identity this build can
    /// finish.
    private nonisolated static func loadFallback() throws -> JourneyBundle {
        // One loader for the whole fleet: JourneyResource resolves the
        // packaged bundle and throws a named error saying which paths it
        // tried, instead of SwiftPM's accessor trapping on a machine that
        // never built this binary.
        let definition = try String(
            decoding: JourneyResource.definitionData(
                resource: GlinaJourney.resourceName,
                bundleName: "GlinaDesktop_GlinaDesktop.bundle"
            ),
            as: UTF8.self
        )
        let bundle = try JourneyRouter.makeBundle(
            canonicalDefinition: definition,
            journeyVersionId: GlinaJourney.fallbackVersionID
        )
        guard bundle.definition.journeyVersion == GlinaJourney.journeyVersion,
              bundle.definition.firstSuccessFact == GlinaJourney.firstSuccessFact
        else {
            throw JourneyClientError.invalid("bundled fallback identity")
        }
        return bundle
    }

    /// Why a replay failed, in words an operator can act on.
    ///
    /// `JourneyClientError` carries no localization, so `localizedDescription`
    /// renders it as "error 3" and names nothing.
    private static func replayFailure(_ error: Error) -> String {
        guard let journeyError = error as? JourneyClientError else {
            return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        switch journeyError {
        case .notStarted:
            return "The walkthrough did not load in this session, so there is nothing to show."
        case .storage:
            return "Walkthrough progress could not be written on this machine."
        case .transport:
            return "The onboarding service could not be reached."
        case let .invalid(reason):
            return reason
        }
    }
}

/// The walkthrough itself: one panel over Glina's window.
///
/// Its words come from the journey definition rather than from this file, so the
/// bundled JSON and a newer central bundle of the same identity read the same
/// on screen. The identifier keys are the fallback, not the copy.
struct GlinaOnboardingOverlay: View {
    let screen: JourneyScreen?
    let errorMessage: String?
    let isWorking: Bool
    let isFinalScreen: Bool
    let stepNumber: Int?
    let advance: () -> Void
    let startSculpting: () -> Void
    let retry: () -> Void

    var body: some View {
        ZStack {
            WisentDesign.canvas.opacity(0.94)
                .ignoresSafeArea()

            WisentPanel(padding: WisentDesign.Space.x6) {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                    HStack(spacing: WisentDesign.Space.x3) {
                        Text("GLINA")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.7)
                            .foregroundStyle(WisentDesign.brand)
                        Spacer()
                        if let stepNumber {
                            WisentBadge("Step \(stepNumber) of 3", symbol: "sparkles", tone: .brand)
                        }
                    }

                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        Text(title)
                            .font(WisentTypography.display(28))
                            .foregroundStyle(WisentDesign.ink)
                        Text(explanation)
                            .font(WisentTypography.body(15))
                            .foregroundStyle(WisentDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(WisentTypeScale.bodyStrong())
                            .foregroundStyle(WisentDesign.danger)
                    }

                    HStack {
                        Spacer()
                        if screen == nil {
                            Button("Try Again", action: retry)
                                .buttonStyle(WisentPrimaryButtonStyle())
                                .disabled(isWorking)
                        } else if isFinalScreen {
                            Button("Go to Sculpt", action: startSculpting)
                                .buttonStyle(WisentPrimaryButtonStyle())
                                .keyboardShortcut(.defaultAction)
                                .disabled(isWorking)
                        } else {
                            Button("Continue", action: advance)
                                .buttonStyle(WisentPrimaryButtonStyle())
                                .keyboardShortcut(.defaultAction)
                                .disabled(isWorking)
                        }
                    }
                }
            }
            .frame(width: 620)
            .padding(WisentDesign.Space.x8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Glina first-run walkthrough")
    }

    private var title: String {
        screen?.presentation.text("title")
            ?? screen?.titleKey
            ?? "First-run walkthrough unavailable"
    }

    private var explanation: String {
        screen?.presentation.text("body")
            ?? screen?.bodyKey
            ?? "The bundled walkthrough could not be loaded. Nothing about your pipeline or credentials has changed."
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }
}
