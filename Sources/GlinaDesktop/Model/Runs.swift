// What a run does: the workflow the draft names, and importing an asset the
// operator chose, each as one finite `glina` command.

import Foundation
import SwiftUI
import WisentErrors

extension GlinaModel {

    func run() async {
        guard !isRunning else { return }
        if let problem = draft.validationProblem {
            failure = problem
            backendStartFailed = false
            WisentFailureReporter.shared.report(
                failurePoint: "glina.run",
                code: "unknown",
                service: "glina",
                detail: problem
            )
            return
        }
        isRunning = true
        result = nil
        failure = nil
        backendStartFailed = false
        liveLog = ""
        outputPaths = []
        startedAt = Date()
        defer { isRunning = false }
        do {
            let client = try await makeClient()
            let outcome: GlinaOutcome
            switch draft.action {
            case .sculpt:
                outcome = try await client.sculpt(prompt: draft.prompt, rounds: draft.rounds, onLog: appendLog)
            case .verify:
                outcome = try await client.verify(path: draft.assetPath, onLog: appendLog)
            case .config:
                outcome = try await client.config()
            case .doctor:
                outcome = try await client.doctor()
            case .create:
                outcome = try await client.create(prompt: draft.prompt, race: draft.race, onLog: appendLog)
            case .animate:
                outcome = try await client.animate(path: draft.assetPath, preset: draft.preset, onLog: appendLog)
            case .showcase:
                outcome = try await client.showcase(asset: draft.showcaseAsset, onLog: appendLog)
            case .declarations:
                outcome = try await client.declarations(
                    kind: draft.declarationKind,
                    verb: draft.declarationVerb,
                    name: draft.declarationName,
                    file: draft.declarationFile
                )
            case .exportConfig:
                outcome = try await client.exportConfig(out: draft.exportPath)
            case .setup:
                outcome = try await client.setup(checkOnly: draft.setupCheckOnly, dryRun: draft.setupDryRun, onLog: appendLog)
            case .assets:
                return
            }
            result = outcome
            outputPaths = outcome.paths
            failure = outcome.refusal
            if let refusal = outcome.refusal {
                WisentFailureReporter.shared.report(
                    failurePoint: "glina.run",
                    code: "unknown",
                    service: "glina",
                    detail: refusal
                )
            }
        } catch let error as GlinaBackendError {
            backendStartFailed = true
            failure = error.errorDescription
            WisentFailureReporter.shared.report(
                failurePoint: "glina.backend_start",
                code: "infra_down",
                service: "glina",
                detail: error.errorDescription
            )
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            WisentFailureReporter.shared.report(
                failurePoint: "glina.run",
                code: "unknown",
                service: "glina",
                detail: failure
            )
        }
    }

    func importAsset(from source: URL) async {
        guard !isRunning else { return }
        isRunning = true
        result = nil
        failure = nil
        assetImport = nil
        importedAssetPath = nil
        backendStartFailed = false
        liveLog = ""
        outputPaths = []
        startedAt = Date()
        defer { isRunning = false }
        do {
            let client = try await makeClient()
            let outcome = try await client.importAsset(source: source.path, onLog: appendLog)
            result = outcome
            outputPaths = outcome.paths
            guard outcome.status == 0,
                  let data = outcome.document.data(using: .utf8),
                  let report = try? JSONDecoder().decode(GlinaAssetImport.self, from: data)
            else {
                failure = outcome.refusal ?? "Glina returned an unreadable workspace import result."
                return
            }
            assetImport = report
            guard report.accepted, let destination = report.path else {
                failure = report.reason ?? "Glina did not accept this asset."
                return
            }
            let url = URL(fileURLWithPath: destination)
            setAssetsDirectory(url.deletingLastPathComponent())
            selectedGLB = url
            draft.assetPath = destination
            draft.action = .assets
            outputPaths = [destination]
            importedAssetPath = destination
        } catch let error as GlinaBackendError {
            backendStartFailed = true
            failure = error.errorDescription
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func makeClient() async throws -> GlinaClient {
        _ = try GlinaCommand.executable()
        return GlinaClient()
    }

    /// Appends one chunk of a command's output, in the order the command
    /// wrote it.
    func appendLog(_ chunk: String) {
        liveLog += chunk
    }
}
