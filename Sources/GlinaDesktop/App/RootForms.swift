// The two forms a workflow is started from, and what the window shows when
// it has finished: the failure or the log, and the paths Glina reported.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

extension GlinaRootView {

    private var sculptForm: some View {
        WisentSectionBox(
            title: "Prompt",
            detail: nil
        ) {
            VStack(spacing: WisentDesign.Space.x3) {
                TextField("gothic dwarven tower, low-poly", text: $model.draft.prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
                Stepper(value: $model.draft.rounds, in: 1...64) {
                    HStack {
                        Text("Max rounds").font(WisentTypeScale.bodyStrong()).foregroundStyle(WisentDesign.ink)
                        Spacer()
                        Text("\(model.draft.rounds)").font(WisentTypeScale.bodyStrong()).foregroundStyle(WisentDesign.ink)
                    }
                }
                .frame(maxWidth: 320)
            }
        }
    }

    // MARK: - Verify

    private var verifyForm: some View {
        WisentSectionBox(
            title: "Asset",
            detail: nil
        ) {
            HStack(spacing: WisentDesign.Space.x3) {
                TextField("/path/to/asset.glb", text: $model.draft.assetPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") { chooseGlb() }
            }
        }
    }

    private func chooseGlb() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "glb") ?? .data]
        panel.message = "Choose a .glb asset to verify."
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.assetPath = url.path
        }
    }


    // MARK: - Results

    private func resultPanel(live: Bool) -> some View {
        let text = live && !model.liveLog.isEmpty ? model.liveLog : model.output
        return Group {
            if let failure = model.failure {
                WisentAlertPanel(
                    tone: .danger,
                    title: model.backendStartFailed ? "Glina unavailable" : "Run failed",
                    detail: failure,
                    actions: model.backendStartFailed
                        ? [WisentAction("Retry", symbol: "arrow.clockwise") { Task { await model.run() } }]
                        : []
                )
            }
            if !text.isEmpty {
                WisentSectionBox(
                    title: model.result?.status == 0 ? "Result" : "Output",
                    detail: nil
                ) {
                    ScrollView(.vertical) {
                        Text(text)
                            .font(WisentTypeScale.identifier())
                            .foregroundStyle(WisentDesign.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 420)
                }
            } else if model.isRunning {
                WisentProgressPanel(
                    title: "Glina is running",
                    detail: "Sculpting may take many rounds. The live log is the source of progress and errors."
                )
            } else {
                WisentEmptyPanel(
                    title: "No result yet",
                    detail: "Fill the required fields and run this workflow. Artifacts stay at the paths Glina reports.",
                    symbol: model.draft.action.symbol
                )
            }
        }
    }

    @ViewBuilder
    private var outputPathsPanel: some View {
        if !model.outputPaths.isEmpty {
            WisentSectionBox(title: "Output", detail: "Paths reported by Glina.") {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                    ForEach(model.outputPaths, id: \.self) { path in
                        HStack(spacing: WisentDesign.Space.x3) {
                            Text(path)
                                .font(WisentTypeScale.identifier())
                                .foregroundStyle(WisentDesign.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            if FileManager.default.fileExists(atPath: path) {
                                Button("Quick Look") { preview(path: path) }
                                Button("Reveal in Finder") { model.revealInFinder(URL(fileURLWithPath: path)) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func preview(path: String) {
        model.presentPreview(urls: [URL(fileURLWithPath: path)], index: 0)
    }

    private func relative(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
