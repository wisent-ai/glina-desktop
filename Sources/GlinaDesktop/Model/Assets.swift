// The assets browser: which directory is open, what is in it, and keeping
// that list true while the backend writes into it.

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
        assetSnapshot = []
        galleryIndex = 0
        refreshAssets()
    }

    func refreshAssets() {
        let selectedPath = currentGalleryAsset(tiles: galleryTiles())?.path
        guard let root = assetsDirectory else {
            assetSnapshot = []
            assetFiles = []
            galleryIndex = 0
            return
        }
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            assetSnapshot = []
            assetFiles = []
            galleryIndex = 0
            return
        }
        var found: [(url: URL, snapshot: AssetSnapshot)] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ["glb", "png", "gif"].contains(ext),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }
            found.append((
                url,
                AssetSnapshot(
                    path: url.path,
                    size: values.fileSize ?? 0,
                    modificationDate: values.contentModificationDate ?? .distantPast
                )
            ))
        }
        found.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        let nextSnapshot = found.map(\.snapshot)
        guard nextSnapshot != assetSnapshot else { return }
        assetSnapshot = nextSnapshot
        assetFiles = found.map(\.url)

        let tiles = galleryTiles()
        if let selectedPath, let index = tiles.firstIndex(where: { $0.path == selectedPath }) {
            galleryIndex = index
        } else {
            galleryIndex = min(galleryIndex, max(tiles.count - 1, 0))
        }
    }

    func startAutomaticAssetRefresh() {
        assetRefreshTask?.cancel()
        assetRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refreshAssets()
            }
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
        panel.currentPreviewItemIndex = max(0, min(index, urls.count - 1))
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

}
