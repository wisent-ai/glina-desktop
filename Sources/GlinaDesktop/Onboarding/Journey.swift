// Reaching the published journey: replaying it on demand, the client this
// app builds, the fallback definition it ships, and how a refusal from Echo
// is turned into a sentence rather than a code.

import Foundation
import WisentDesignSystem
import WisentOnboarding

extension GlinaOnboarding {
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

    func bootstrap() async throws -> (JourneyClient, JourneyProgress) {
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
    func expose(using client: JourneyClient) async throws {
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
    static func replayFailure(_ error: Error) -> String {
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
