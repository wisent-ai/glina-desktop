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
