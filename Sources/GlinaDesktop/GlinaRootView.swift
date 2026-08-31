import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

struct GlinaRootView: View {
    @ObservedObject var model: GlinaModel

    var body: some View {
        WisentScreen(
            title: model.draft.action.title,
            scope: "Glina",
            freshness: model.startedAt.map { "ran \(relative($0))" } ?? "not run yet",
            actions: screenActions,
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                        content
                    }
                    .padding(WisentDesign.Space.x6)
                    .frame(maxWidth: 900, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1_100, minHeight: 720)
    }

    private var screenActions: [WisentAction] {
        guard model.draft.action != .assets else { return [] }
        return [
            WisentAction(
                model.isRunning ? "Running…" : "Run",
                symbol: "play.fill",
                kind: .primary,
                isEnabled: !model.isRunning && model.draft.validationProblem == nil
            ) { Task { await model.run() } }
        ]
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
            Text("WORKFLOWS")
                .font(WisentTypeScale.eyebrow())
                .foregroundStyle(WisentDesign.muted)
                .padding(.bottom, WisentDesign.Space.x2)
            ForEach(GlinaAction.allCases) { action in
                Button {
                    model.select(action)
                } label: {
                    HStack(spacing: WisentDesign.Space.x3) {
                        Image(systemName: action.symbol).frame(width: 18)
                        Text(action.title)
                        Spacer()
                    }
                    .font(WisentTypeScale.bodyStrong())
                    .foregroundStyle(model.draft.action == action ? WisentDesign.ink : WisentDesign.secondary)
                    .padding(.horizontal, WisentDesign.Space.x3)
                    .frame(height: 36)
                    .background(
                        model.draft.action == action ? WisentDesign.brandSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Glina runs as a local backend. Blender stays behind the Blender MCP server, secrets behind Skarbiec, models behind Brama.")
                .font(WisentTypeScale.caption())
                .foregroundStyle(WisentDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WisentDesign.Space.x4)
        .frame(width: 220)
        .background(WisentDesign.canvasMuted)
    }

    @ViewBuilder
    private var content: some View {
        switch model.draft.action {
        case .sculpt:
            sculptForm
            resultPanel(live: true)
            outputPathsPanel
        case .verify:
            verifyForm
            resultPanel(live: true)
            outputPathsPanel
        case .config, .blenderHealth, .welesTools:
            simpleForm
            resultPanel(live: false)
        case .assets:
            GlinaAssetsView(model: model)
        }
    }

    // MARK: - Sculpt

    private var sculptForm: some View {
        WisentSectionBox(
            title: "Prompt",
            detail: "What to sculpt. The LLM drives Blender through MCP round by round until the GLB passes the gate."
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
            detail: "The .glb file the structural quality gate inspects."
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

    // MARK: - Config / health / tools

    private var simpleForm: some View {
        WisentSectionBox(title: detailTitle, detail: detailText) {
            EmptyView()
        }
    }

    private var detailTitle: String {
        switch model.draft.action {
        case .config: return "Configuration"
        case .blenderHealth: return "Blender session"
        default: return "Browser layer"
        }
    }

    private var detailText: String {
        switch model.draft.action {
        case .config:
            return "Validates the pipeline config and resolves Skarbiec references; every secret is redacted before anything is shown."
        case .blenderHealth:
            return "MCP handshake plus an execute probe against the live Blender session."
        default:
            return "Lists the browser-layer tools the Weles MCP server exposes."
        }
    }

    // MARK: - Results

    private func resultPanel(live: Bool) -> some View {
        let text = live && !model.liveLog.isEmpty ? model.liveLog : model.output
        return Group {
            if let failure = model.failure {
                WisentAlertPanel(
                    tone: .danger,
                    title: model.backendStartFailed ? "Backend unavailable" : "Glina refused the workflow",
                    detail: failure,
                    actions: model.backendStartFailed
                        ? [WisentAction("Retry", symbol: "arrow.clockwise") { Task { await model.run() } }]
                        : []
                )
            }
            if !text.isEmpty {
                WisentSectionBox(
                    title: model.result?.status == 0 ? "Result" : "Output",
                    detail: live ? "The backend's own output as it streams in." : nil
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
                WisentLoadingPanel(
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
