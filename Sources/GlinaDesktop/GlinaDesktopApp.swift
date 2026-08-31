import SwiftUI
import WisentDesktopUpdate

@main
struct GlinaDesktopApp: App {
    @StateObject private var model = GlinaModel(assetsDirectory: Self.launchAssetsDirectory())
    @StateObject private var updater = WisentUpdater()

    /// `--assets-dir PATH` preselects the sculpt output directory.
    private static func launchAssetsDirectory() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--assets-dir"),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    var body: some Scene {
        WindowGroup("Glina") {
            GlinaRootView(model: model)
                .onAppear { model.applyLaunchOptions() }
                // Every fact Glina reports is selectable, and therefore
                // copyable. This window exists to state things a person then
                // quotes somewhere else — an assets directory, an output path
                // the backend just wrote, a .glb filename, a failure sentence,
                // the backend's streamed log — and SwiftUI's `Text` refuses
                // selection on macOS unless a view asks for it, which left
                // most of this window's text dead to Cmd-C while six sites had
                // been fixed one at a time.
                //
                // `.textSelection` travels through the environment, so one call
                // on the window's whole content covers every screen, present
                // and future, including the result, loading and empty panels
                // that `GlinaRootView` swaps between as branches. That is why
                // the rule is here and not inside the root view: those panels
                // are siblings of each other, so no inner view sees them all.
                // The six per-site calls are removed; keeping them beside the
                // rule would leave two places answering the same question.
                .textSelection(.enabled)
        }
        .defaultSize(width: 1_240, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                WisentCheckForUpdatesCommand(updater: updater)
            }
        }
    }
}
