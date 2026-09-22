import Foundation
import Quartz
import SwiftUI
import WisentErrors

enum GallerySort: String, CaseIterable, Identifiable {
    case nameAscending, nameDescending, newestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nameAscending: return "Name A→Z"
        case .nameDescending: return "Name Z→A"
        case .newestFirst: return "Newest first"
        }
    }
}
private struct AssetSnapshot: Hashable {
    let path: String
    let size: Int
    let modificationDate: Date
}


@MainActor
final class GlinaModel: ObservableObject {
    @Published var draft = GlinaCommandDraft()
    @Published var isRunning = false
    @Published var result: GlinaOutcome?
    @Published var failure: String?
    @Published var startedAt: Date?
    /// Live log streamed by the backend, in the backend's own order.
    @Published var liveLog = ""
    /// The last failure came from starting the backend itself, so the panel
    /// offers a Retry.
    @Published var backendStartFailed = false
    @Published var outputPaths: [String] = []
    @Published var assetImport: GlinaAssetImport?
    @Published var importedAssetPath: String?

    // Assets browser.
    @Published var assetsDirectory: URL?
    @Published var assetFiles: [URL] = []
    var assetSnapshot: [AssetSnapshot] = []
    var assetRefreshTask: Task<Void, Never>?

    /// Strongly retained Quick Look controller — QLPreviewPanel's dataSource
    /// is assigned, not retained, so something must own it.
    @Published var previewController: AssetPreviewController?

    // Gallery browsing: one focused element, arrows/strip to move, sort order.
    @Published var gallerySort: GallerySort = .nameAscending
    @Published var galleryIndex = 0
    @Published var focusPath: String?
    // MARK: - Animation preview
    //
    // The app never renders glTF itself: the backend walks the same Blender
    // MCP bridge as every other workflow and hands back a looping GIF, which
    // NSImageView plays inline.

    @Published var animationClip = ""
    @Published var isRenderingAnimation = false
    @Published var animationNote: String?
    @Published var animatedPreviewURL: URL?
    @Published var selectedGLB: URL?

    /// `Glina --assets-dir PATH` opens straight onto an output directory.
    init(assetsDirectory: URL? = nil) {
        self.assetsDirectory = assetsDirectory
        refreshAssets()
        startAutomaticAssetRefresh()
    }

    deinit {
        assetRefreshTask?.cancel()
    }

    let backend = GlinaBackendProcess()

    /// Launch flags: `--assets-dir PATH` selects the output directory,
    /// `--play PATH` opens the window already on that element.
    func applyLaunchOptions() {
        let arguments = ProcessInfo.processInfo.arguments
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--assets-dir" where arguments.indices.contains(index + 1):
                setAssetsDirectory(URL(fileURLWithPath: arguments[index + 1]))
            case "--play" where arguments.indices.contains(index + 1):
                let url = URL(fileURLWithPath: arguments[index + 1])
                if FileManager.default.fileExists(atPath: url.path) {
                    focusPath = url.path
                }
                draft.action = .assets
            default:
                break
            }
            index += 1
        }
    }

    var output: String {
        result?.document ?? ""
    }


    func select(_ action: GlinaAction) {
        draft.action = action
        result = nil
        failure = nil
        backendStartFailed = false
        liveLog = ""
        outputPaths = []
    }
}
