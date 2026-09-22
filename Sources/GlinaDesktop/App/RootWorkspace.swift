// What the window offers besides a run: importing an existing asset through
// the same quality gate, and replaying the first-run guide.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

extension GlinaRootView {

    private var workspaceAndFirstRun: some View {
        WisentSectionBox(
            title: "Workspace and first run",
            detail: "Import an existing GLB through Glina's quality gate, or replay the first-run guide."
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                HStack(spacing: WisentDesign.Space.x3) {
                    Button("Import GLB…") { chooseAssetForImport(onboardingAttempt: false) }
                        .buttonStyle(WisentPrimaryButtonStyle())
                        .disabled(model.isRunning)
                    Button("Show first-run guide again") { showWalkthroughAgain() }
                        .buttonStyle(WisentSecondaryButtonStyle())
                        .disabled(isReplaying)
                }
                if let imported = model.assetImport {
                    Text(importSummary(imported))
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(imported.accepted ? WisentDesign.success : WisentDesign.danger)
                }
                if walkthrough != .idle {
                    WisentMutationBar(outcome: walkthrough) { walkthrough = .idle }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseAssetForImport(onboardingAttempt: Bool) {
        guard !model.isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "glb") ?? .data]
        panel.message = "Choose a GLB for Glina to validate and keep in its workspace."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if onboardingAttempt {
            onboarding.prepareToImport()
        }
        Task {
            await model.importAsset(from: url)
            if onboardingAttempt {
                if let destination = model.importedAssetPath {
                    await onboarding.observeImportedAsset(path: destination)
                } else {
                    onboarding.importFailed(reason: model.failure ?? "Glina did not accept this asset.")
                }
            }
        }
    }

    private func importSummary(_ report: GlinaAssetImport) -> String {
        if let path = report.path {
            return "\(report.status.capitalized): \(path)"
        }
        return "\(report.status.capitalized): \(report.reason ?? "No workspace state changed.")"
    }

    private var isReplaying: Bool { onboarding.isWorking || walkthrough.isWorking }

    /// Resets the journey and lets the window present it again.
    ///
    /// Nothing here reaches for a sheet: the walkthrough has exactly one
    /// presentation in this app — the overlay this view stacks over the whole
    /// window — and the reset is what puts it back, in this session, because
    /// that is what was asked for rather than a note to look again after the
    /// next launch.
    ///
    /// The local `.working` line is what closes the control, not
    /// `onboarding.isWorking`: the journey does not raise that flag until the
    /// task below is scheduled, and a second press lands in the gap.
    private func showWalkthroughAgain() {
        guard !isReplaying else { return }
        walkthrough = .working("Starting the walkthrough…")
        Task { walkthrough = await onboarding.replay() }
    }

    // MARK: - Sculpt
}
