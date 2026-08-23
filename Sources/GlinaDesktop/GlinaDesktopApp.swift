import SwiftUI
import WisentDesktopUpdate

@main
struct GlinaDesktopApp: App {
    @StateObject private var model = GlinaModel()
    @StateObject private var updater = WisentUpdater()

    var body: some Scene {
        WindowGroup("Glina") {
            GlinaRootView(model: model)
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
