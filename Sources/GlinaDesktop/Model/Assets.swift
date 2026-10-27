// The assets browser: which directory is open, what is in it, and keeping
// that list true while the backend writes into it, by listing the tree again
// after every change FSEvents reports under it.

import AppKit
import Foundation
import Quartz

extension GlinaModel {
    // MARK: - Assets browser

    func chooseAssetsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose the directory Glina writes assets into."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setAssetsDirectory(url)
    }

    func setAssetsDirectory(_ url: URL) {
        assetsDirectory = url
        clearAssets()
        refreshAssets()
        watchAssets()
    }

    /// Lists the open directory. With no directory open there is nothing to
    /// list; a tree that cannot be listed is reported with its cause, and the
    /// list keeps what it showed when it was last read.
    func refreshAssets() {
        guard let root = assetsDirectory else { return clearAssets() }
        switch Result(catching: { try Self.listAssets(under: root) }) {
        case .success(let found):
            show(found)
        case .failure(let error):
            failure = error.localizedDescription
        }
    }

    private static func listAssets(under root: URL) throws -> [(url: URL, snapshot: AssetSnapshot)]
    {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .contentTypeKey, .fileSizeKey, .contentModificationDateKey,
        ]
        var refusal: AssetListingFailure?
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    refusal = AssetListingFailure(path: url.path, cause: error.localizedDescription)
                    return false
                }
            )
        else {
            throw AssetListingFailure(
                path: root.path, cause: "FileManager returned no enumerator for it")
        }
        var found: [(url: URL, snapshot: AssetSnapshot)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true,
                let type = values.contentType,
                AssetKind(contentType: type) != nil
            else { continue }
            found.append(
                (
                    url,
                    AssetSnapshot(
                        path: url.path,
                        size: values.fileSize,
                        modificationDate: values.contentModificationDate
                    )
                ))
        }
        if let refusal { throw refusal }
        return found.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }

    private func show(_ found: [(url: URL, snapshot: AssetSnapshot)]) {
        let nextSnapshot = found.map(\.snapshot)
        guard nextSnapshot != assetSnapshot else { return }
        let selectedPath = currentGalleryAsset(tiles: galleryTiles())?.path
        assetSnapshot = nextSnapshot
        assetFiles = found.map(\.url)

        let tiles = galleryTiles()
        if let selectedPath, let index = tiles.firstIndex(where: { $0.path == selectedPath }) {
            galleryIndex = index
        } else if let last = tiles.indices.last {
            galleryIndex = min(galleryIndex, last)
        } else {
            galleryIndex = tiles.startIndex
        }
    }

    private func clearAssets() {
        assetSnapshot.removeAll()
        assetFiles.removeAll()
        galleryIndex = .zero
    }

    /// Opens a watch over the chosen directory, replacing the previous one.
    /// A watch that cannot be opened is reported with its cause, and the list
    /// then shows what was there when it was last read.
    func watchAssets() {
        assetWatch = nil
        guard let root = assetsDirectory else { return }
        let opened = Result {
            try AssetTreeWatch(root: root) { [weak self] in
                self?.refreshAssets()
            }
        }
        switch opened {
        case .success(let watch):
            assetWatch = watch
        case .failure(let error):
            failure = error.localizedDescription
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func presentPreview(urls: [URL], index: Int) {
        guard !urls.isEmpty else { return }
        let controller = AssetPreviewController(items: urls)
        previewController = controller
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = controller
        panel.delegate = controller
        panel.currentPreviewItemIndex = min(
            max(index, urls.startIndex), urls.index(before: urls.endIndex))
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

}

/// A tree the assets browser could not list, with the path FileManager
/// stopped at and the reason it gave.
struct AssetListingFailure: LocalizedError {
    let path: String
    let cause: String

    var errorDescription: String? {
        "Glina cannot list the assets under \(path): \(cause)."
    }
}
