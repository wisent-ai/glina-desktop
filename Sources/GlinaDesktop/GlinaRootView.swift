import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

struct GlinaRootView: View {
    @ObservedObject var model: GlinaModel
    @ObservedObject var onboarding: GlinaOnboarding

    /// How the last replay from Check Config ended. Held by the screen rather
    /// than by the journey so leaving Check Config clears the line instead of
    /// carrying a stale "Started." onto Sculpt.
    @State private var walkthrough: WisentMutationOutcome = .idle

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
        .task {
            await onboarding.start()
        }
        // First success is observed, never asserted: the walkthrough finishes
        // when Glina reports a `.glb` it wrote, not when a button is pressed.
        .onChange(of: model.sculptedAsset) { _, asset in
            guard let asset else { return }
            Task { await onboarding.observeSculptedAsset(path: asset) }
        }
        .overlay {
            if onboarding.isPresented {
                GlinaOnboardingOverlay(
                    screen: onboarding.screen,
                    errorMessage: onboarding.errorMessage,
                    isWorking: onboarding.isWorking,
                    isFinalScreen: onboarding.isFinalScreen,
                    stepNumber: onboarding.stepNumber,
                    advance: { Task { await onboarding.advance() } },
                    startSculpting: {
                        model.select(.sculpt)
                        onboarding.prepareToSculpt()
                    },
                    retry: { Task { await onboarding.retry() } }
                )
            }
        }
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
        // Glina has no Settings window and no preferences pane: every screen in
        // this sidebar runs one `glina` command and reports its answer. Check
        // Config is the operator-facing one — it is where someone goes to ask
        // what this installation is actually configured to do — so the one
        // control in the app that writes something instead of reporting
        // something sits last on it, under the facts it does not change.
        case .config:
            resultPanel(live: false)
            firstRunWalkthrough
        case .blenderHealth, .welesTools:
            resultPanel(live: false)
        case .assets:
            GlinaAssetsView(model: model)
        }
    }

    // MARK: - First-run walkthrough

    private var firstRunWalkthrough: some View {
        WisentSectionBox(
            title: "First-run walkthrough",
            detail: "See the walkthrough this product shows on a first run."
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Button("Show it again") { showWalkthroughAgain() }
                    .buttonStyle(WisentSecondaryButtonStyle())
                    .disabled(isReplaying)
                if walkthrough != .idle {
                    WisentMutationBar(outcome: walkthrough) { walkthrough = .idle }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
