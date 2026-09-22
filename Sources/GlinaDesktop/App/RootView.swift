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
        // First success is observed only after Glina accepts and persists an
        // import. Picker selection alone never reaches the journey.
        .overlay {
            if onboarding.isPresented {
                GlinaOnboardingOverlay(
                    screen: onboarding.screen,
                    errorMessage: onboarding.errorMessage,
                    isWorking: onboarding.isWorking,
                    isFinalScreen: onboarding.isFinalScreen,
                    stepNumber: onboarding.stepNumber,
                    advance: { Task { await onboarding.advance() } },
                    importAsset: { chooseAssetForImport(onboardingAttempt: true) },
                    retry: { Task { await onboarding.retry() } }
                )
            }
        }
    }

    private var screenActions: [WisentAction] {
        guard model.draft.action != .assets else { return [] }
        return [
            // The verb stays "Run" while the run is in flight: the shell
            // shimmers the label in place and refuses a second press, so
            // `isEnabled` states only what the operator can still fix.
            WisentAction(
                "Run",
                symbol: "play.fill",
                kind: .primary,
                isEnabled: model.draft.validationProblem == nil,
                isBusy: model.isRunning
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
        // Glina has no separate Settings window. Check Config is the
        // installation/settings surface, so workspace import and onboarding
        // replay live below the reported configuration.
        case .config:
            resultPanel(live: false)
            workspaceAndFirstRun
        case .blenderHealth, .welesTools:
            resultPanel(live: false)
        case .assets:
            GlinaAssetsView(model: model)
        }
    }

    // MARK: - First-run walkthrough
}
