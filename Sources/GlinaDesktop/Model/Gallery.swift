// Browsing the gallery: one tile per asset, the order the operator chose,
// and the element the window is currently on.

import Foundation

extension GlinaModel {
    // MARK: - Gallery browsing

    /// One tile per asset: every .glb model, plus renders that belong to no
    /// model. The order follows the operator's sort choice.
    func galleryTiles() -> [URL] {
        let models = assetFiles.filter { $0.pathExtension.lowercased() == "glb" }
        let groupedStems = Set(models.map { $0.deletingPathExtension().lastPathComponent })
        let orphans = assetFiles
            .filter { $0.pathExtension.lowercased() != "glb" }
            .filter { preview in !groupedStems.contains { stem in preview.deletingPathExtension().lastPathComponent.hasPrefix(stem) } }
        let ascending: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        var tiles = models.sorted(by: ascending) + orphans.sorted(by: ascending)
        switch gallerySort {
        case .nameAscending:
            break
        case .nameDescending:
            tiles.reverse()
        case .newestFirst:
            tiles.sort { modificationDate($0) > modificationDate($1) }
        }
        return tiles
    }

    func modificationDate(_ url: URL) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
    }

    func currentGalleryAsset(tiles: [URL]) -> URL? {
        guard !tiles.isEmpty else { return nil }
        return tiles[min(max(galleryIndex, 0), tiles.count - 1)]
    }

    func stepGallery(_ direction: Int, count: Int) {
        guard count > 0 else { return }
        galleryIndex = ((galleryIndex + direction) % count + count) % count
    }

    /// `--play PATH` lands the viewer on that element once the gallery exists.
    func focusLaunchedAsset() {
        guard let path = focusPath else { return }
        let tiles = galleryTiles()
        if let index = tiles.firstIndex(where: { $0.path == path }) {
            galleryIndex = index
        } else {
            // A preview grouped into a .glb is not a standalone tile. Focus
            // the owning model instead (smok-flap-preview.gif → smok.glb).
            let previewStem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let index = tiles.firstIndex(where: { tile in
                tile.pathExtension.lowercased() == "glb"
                    && previewStem.hasPrefix(tile.deletingPathExtension().lastPathComponent)
            }) {
                galleryIndex = index
            }
        }
        focusPath = nil
    }

}
