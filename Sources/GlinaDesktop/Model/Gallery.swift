// Browsing the gallery: one tile per asset, the order the operator chose,
// and the element the window is currently on.

import Foundation

extension GlinaModel {
    // MARK: - Gallery browsing

    /// One tile per asset: every model, plus renders that belong to no
    /// model. The order follows the operator's sort choice.
    func galleryTiles() -> [URL] {
        let models = assetFiles.filter { assetKind(of: $0) == .model }
        let groupedStems = Set(models.map { $0.deletingPathExtension().lastPathComponent })
        let orphans =
            assetFiles
            .filter { assetKind(of: $0) != .model }
            .filter { preview in
                !groupedStems.contains { stem in
                    preview.deletingPathExtension().lastPathComponent.hasPrefix(stem)
                }
            }
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
            tiles.sort { isNewer($0, than: $1) }
        }
        return tiles
    }

    /// Whether `url` was modified after `other`, by the dates the listing
    /// read. A file the system recorded no date for sorts after every dated
    /// one, since nothing says when it was made.
    private func isNewer(_ url: URL, than other: URL) -> Bool {
        let modified = { (file: URL) in self.assetSnapshot[file.path]?.modificationDate }
        switch (modified(url), modified(other)) {
        case let (.some(date), .some(otherDate)):
            return date > otherDate
        case (.some, .none):
            return true
        case (.none, _):
            return false
        }
    }

    /// The tile the window is on: the one at the gallery index, or the
    /// nearest end when the index has run past either end.
    func currentGalleryAsset(tiles: [URL]) -> URL? {
        if tiles.indices.contains(galleryIndex) {
            return tiles[galleryIndex]
        }
        return galleryIndex < tiles.startIndex ? tiles.first : tiles.last
    }

    /// The position the gallery shows, counted from its first tile.
    func galleryPosition(tiles: [URL]) -> Int {
        tiles.indices.filter { $0 <= galleryIndex }.count
    }

    /// Moves to the next tile, from the last back to the first.
    func showNextTile(of tiles: [URL]) {
        guard !tiles.isEmpty else { return }
        let next = tiles.index(after: galleryIndex)
        galleryIndex = tiles.indices.contains(next) ? next : tiles.startIndex
    }

    /// Moves to the previous tile, from the first back to the last.
    func showPreviousTile(of tiles: [URL]) {
        guard !tiles.isEmpty else { return }
        galleryIndex =
            galleryIndex > tiles.startIndex
            ? tiles.index(before: galleryIndex) : tiles.index(before: tiles.endIndex)
    }

    /// `--play PATH` lands the viewer on that element once the gallery exists.
    func focusLaunchedAsset() {
        guard let path = focusPath else { return }
        let tiles = galleryTiles()
        if let index = tiles.firstIndex(where: { $0.path == path }) {
            galleryIndex = index
        } else {
            // A preview grouped into a model is not a standalone tile. Focus
            // the owning model instead (smok-flap-preview.gif → smok.glb).
            let previewStem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let index = tiles.firstIndex(where: { tile in
                assetKind(of: tile) == .model
                    && previewStem.hasPrefix(tile.deletingPathExtension().lastPathComponent)
            }) {
                galleryIndex = index
            }
        }
        focusPath = nil
    }

}
