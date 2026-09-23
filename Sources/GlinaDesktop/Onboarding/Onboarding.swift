import Foundation
import SwiftUI
import WisentDesignSystem
import WisentOnboarding

/// The identity of the journey this build can actually finish, in one place off
/// the main actor: the transport below runs on whatever executor Echo's client
/// calls it from, and the controller runs on the main actor, and both compare
/// against these exact strings.
enum GlinaJourney {
    static let productID = "glina-desktop"
    static let journeyID = "first-use"
    static let journeyVersion = "2026-09-23.1"
    static let firstSuccessFact = "asset_imported"
    /// The evidence revision and the storage namespace keep the first
    /// version's names: a revision that only corrects copy must not restart an
    /// installation's walkthrough.
    static let evidenceRevision = "glina-desktop-first-use-2026-09-05"
    static let storageNamespace = "ai.wisent.glina.onboarding.2026-09-05.1"
    static let installationIDKey = "ai.wisent.glina.onboarding.installation-id"
    static let fallbackVersionID = UUID(uuidString: "86046D82-A27F-4C61-88D7-D96D6275BF51")!
    static let resourceName = "glina-desktop-first-use"
    static let tokenEnvironmentKey = "GLINA_DESKTOP_STADO_INTEGRATION_TOKEN"
}

/// Echo's transport, with Glina's identity checked before the central bundle is
/// trusted.
///
/// The control plane can serve a newer journey than this build was written
/// against. Accepting it silently would put a screen on the window whose final
/// step Glina has no way to observe — the fact name is compiled into
/// `observeImportedAsset` — and first use would never finish. A mismatch is
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

/// Glina's first-run walkthrough: three screens ending in a persisted import.
///
/// The final action only moves the overlay aside while the system file picker
/// and Glina's own workspace import run. Completion is recorded only after the
/// backend returns the accepted destination path.
@MainActor
final class GlinaOnboarding: ObservableObject {
    enum State: Equatable {
        case loading
        case presenting
        case awaitingImport
        case completed
    }

    @Published var screen: JourneyScreen?
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published var state: State = .loading

    var client: JourneyClient?
    private var hasStarted = false
    var exposedScreenID: String?

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

    /// Let the system picker and backend import proceed without claiming
    /// completion. A refusal can restore this screen with its exact reason.
    func prepareToImport() {
        guard isFinalScreen else { return }
        errorMessage = nil
        state = .awaitingImport
    }

    /// First success is an accepted workspace destination, not a picker choice.
    func observeImportedAsset(path: String) async {
        guard let client, state == .awaitingImport || state == .presenting else { return }
        do {
            let completed = try await client.complete(
                evidence: [GlinaJourney.firstSuccessFact: .boolean(true)],
                evidenceRevision: "asset-imported:\(path)"
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

    func importFailed(reason: String) {
        guard state == .awaitingImport else { return }
        errorMessage = reason
        state = .presenting
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
}
