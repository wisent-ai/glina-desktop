// How the assets browser draws one asset: a model by the render the pipeline
// made of it, a still or an animation as itself, in the focused view and in
// the filmstrip below it.

import SwiftUI
import WisentDesignSystem

/// The browser's sizes, each one the design system's own: a filmstrip tile
/// is two context bars tall, the strip leaves one spacing step around it,
/// and a focused preview is never taller than the shell's inspector is wide.
enum AssetsLayout {
    static let tileSide = WisentAppLayout.contextBarHeight + WisentAppLayout.contextBarHeight
    static let stripHeight = tileSide + WisentDesign.Space.x2
    static let previewHeight = WisentAppLayout.inspectorWidth
    static let selectionStroke = WisentDesign.hairline + WisentDesign.hairline
}

extension GlinaAssetsView {
    func filmstrip(tiles: [URL]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WisentDesign.Space.x2) {
                    ForEach(Array(tiles.enumerated()), id: \.element) { index, url in
                        ZStack {
                            Rectangle().fill(WisentDesign.canvasMuted)
                            tileContent(url)
                                .padding(WisentDesign.Space.x1)
                        }
                        .frame(width: AssetsLayout.tileSide, height: AssetsLayout.tileSide)
                        .clipShape(RoundedRectangle(cornerRadius: WisentDesign.Radius.small))
                        .overlay(
                            RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                                .stroke(
                                    index == model.galleryIndex ? WisentDesign.brand : .clear,
                                    lineWidth: AssetsLayout.selectionStroke)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { model.galleryIndex = index }
                        .id(index)
                    }
                }
            }
            .frame(height: AssetsLayout.stripHeight)
            .onChange(of: model.galleryIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    @ViewBuilder
    func tileContent(_ url: URL) -> some View {
        switch model.assetKind(of: url) {
        case .animation, .still:
            imageOrPlaceholder(url)
        case .model, .none:
            if let preview = matchedPreview(for: url) {
                imageOrPlaceholder(preview)
            } else {
                Image(systemName: "cube.transparent")
                    .font(WisentTypography.display())
                    .foregroundStyle(WisentDesign.muted)
            }
        }
    }

    @ViewBuilder
    private func imageOrPlaceholder(_ url: URL) -> some View {
        if model.assetKind(of: url) == .animation {
            AnimatedGifPlayer(url: url)
                .aspectRatio(contentMode: .fit)
        } else if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "photo")
                .foregroundStyle(WisentDesign.muted)
        }
    }

    /// A model tile shows the rendered sibling the pipeline already produced
    /// (smok.glb → smok-flap-preview.gif, kamien.glb → kamien-preview.png).
    private func matchedPreview(for modelURL: URL) -> URL? {
        let stem = modelURL.deletingPathExtension().lastPathComponent
        return model.assetFiles.first { candidate in
            candidate.deletingLastPathComponent() == modelURL.deletingLastPathComponent()
                && candidate != modelURL
                && model.assetKind(of: candidate) != .model
                && candidate.deletingPathExtension().lastPathComponent.hasPrefix(stem)
        }
    }
}
