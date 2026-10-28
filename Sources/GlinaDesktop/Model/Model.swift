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
/// What a listed asset looked like when it was read, so a listing that finds
/// nothing new leaves the browser as it is. The system may report no size or
/// date for a file; that absence is compared like any other value.
struct AssetSnapshot: Hashable {
    let path: String
    /// What the file is, read from the content type the system records.
    let kind: AssetKind
    let size: Int?
    let modificationDate: Date?
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
    @Published var variantParent = ""

    // Assets browser.
    @Published var assetsDirectory: URL?
    @Published var assetFiles: [URL] = []
    /// What the last listing read for each listed file, keyed by its path, so
    /// a tile, a match or a sort comparison finds its file in constant time.
    var assetSnapshot: [String: AssetSnapshot] = [:]
    /// Why the open directory could not be listed the last time it was read;
    /// cleared by the next listing that succeeds.
    @Published var assetsListingFailure: String?
    /// Why the open directory is not watched for changes; cleared when a
    /// watch opens.
    @Published var assetsWatchFailure: String?
    var assetWatch: AssetTreeWatch?

    /// Strongly retained Quick Look controller — QLPreviewPanel's dataSource
    /// is assigned, not retained, so something must own it.
    @Published var previewController: AssetPreviewController?

    // Gallery browsing: one focused element, arrows/strip to move, sort order.
    @Published var gallerySort: GallerySort = .nameAscending
    @Published var galleryIndex: Int = .zero
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
    @Published var isRenderingScene = false
    @Published var scenePreviewImage: NSImage?
    @Published var sceneSourcePath: String?
    @Published var sceneNote: String?

    /// `Glina --assets-dir PATH` opens straight onto an output directory.
    init(assetsDirectory: URL? = nil) {
        self.assetsDirectory = assetsDirectory
        refreshAssets()
        watchAssets()
    }

    /// Launch flags: `--assets-dir PATH` selects the output directory,
    /// `--play PATH` opens the window already on that element.
    func applyLaunchOptions() {
        let arguments = ProcessInfo.processInfo.arguments
        for (flag, value) in zip(arguments, arguments.dropFirst()) {
            switch flag {
            case "--assets-dir":
                setAssetsDirectory(URL(fileURLWithPath: value))
            case "--play":
                let url = URL(fileURLWithPath: value)
                if FileManager.default.fileExists(atPath: url.path) {
                    focusPath = url.path
                }
                draft.action = .assets
            default:
                break
            }
        }
    }

    /// The document the last run printed; before any run there is none.
    var output: String {
        guard let result else { return String() }
        return result.document
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
