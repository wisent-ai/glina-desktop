import AppKit
import SwiftUI
import WisentDesignSystem
import WisentDesktopUpdate

/// Everything inside Glina's window, in one type because two window trees
/// render it: the `WindowGroup` scene, and the delegate's fallback window for
/// the launch where AppKit had state to restore and SwiftUI opened nothing.
/// Whatever this view says about the window's content is therefore true of
/// both windows, which is the only way the text-selection rule below can cover
/// both and remain a single call site.
struct GlinaWindowContent: View {
    @ObservedObject var model: GlinaModel
    @ObservedObject var onboarding: GlinaOnboarding

    var body: some View {
        GlinaRootView(model: model, onboarding: onboarding)
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
}

/// Owns the model and the first-run walkthrough, so the scene and the fallback
/// window share one instance of each — two controllers would present the
/// walkthrough twice and record two attempts for one launch — and calls
/// `wisentEnsureWindow` for the launch where the scene produces no window at
/// all; see that function for the measurements.
@MainActor
final class GlinaDesktopAppDelegate: NSObject, NSApplicationDelegate {
    let model = GlinaModel(assetsDirectory: GlinaDesktopAppDelegate.launchAssetsDirectory())
    let onboarding = GlinaOnboarding()
    private var fallbackWindow: NSWindow?

    /// `--assets-dir PATH` preselects the sculpt output directory.
    private static func launchAssetsDirectory() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--assets-dir"),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A turn later: at `applicationDidFinishLaunching` the scene has not
        // had its chance to open a window yet, so asking now would always
        // answer "none" and build a second, redundant window.
        DispatchQueue.main.async { [self] in
            fallbackWindow = wisentEnsureWindow(
                title: "Glina",
                size: CGSize(width: 1_240, height: 820)
            ) {
                GlinaWindowContent(model: self.model, onboarding: self.onboarding)
            }
        }
    }
}

@main
struct GlinaDesktopApp: App {
    @NSApplicationDelegateAdaptor(GlinaDesktopAppDelegate.self) private var delegate
    @StateObject private var updater = WisentUpdater()

    var body: some Scene {
        WindowGroup("Glina") {
            GlinaWindowContent(model: delegate.model, onboarding: delegate.onboarding)
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
