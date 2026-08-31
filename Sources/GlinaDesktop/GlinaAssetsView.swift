import ImageIO
import Quartz
import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

/// Quick Look over the produced artifacts. The panel is driven directly —
/// the data source is installed before the panel is keyed, so no responder
/// in the chain has to opt in first.
@MainActor
final class AssetPreviewController: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    let items: [URL]

    init(items: [URL]) {
        self.items = items
        super.init()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as QLPreviewItem
    }

}

@MainActor
struct GlinaAssetsView: View {
    @ObservedObject var model: GlinaModel


    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            WisentSectionBox(
                title: "Output directory",
                detail: "Where Glina writes sculpted assets. The browser lists every .glb and .png beneath it."
            ) {
                HStack(spacing: WisentDesign.Space.x3) {
                    Text(model.assetsDirectory?.path ?? "No directory chosen")
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(model.assetsDirectory == nil ? WisentDesign.muted : WisentDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button("Choose Directory") { model.chooseAssetsDirectory() }
                    if model.assetsDirectory != nil {
                        Button("Refresh") { model.refreshAssets() }
                    }
                }
            }

            if model.assetsDirectory != nil {
                assetsList
                animationSection
            } else {
                WisentEmptyPanel(
                    title: "No output directory",
                    detail: "Choose the folder your sculpted assets are saved in, then browse what Glina produced.",
                    symbol: "cube.transparent"
                )
            }
        }
    }
    private func presentPreview(urls: [URL], index: Int) {
        model.presentPreview(urls: urls, index: index)
    }

    private var assetsList: some View {
        let tiles = model.galleryTiles()
        return WisentSectionBox(
            title: "Gallery",
            detail: "Arrows (or ← →) move between elements; the strip below jumps straight to one."
        ) {
            if tiles.isEmpty {
                Text("No assets under this directory yet.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
            } else {
                HStack(spacing: WisentDesign.Space.x3) {
                    Picker("Sort", selection: $model.gallerySort) {
                        ForEach(GallerySort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                    Spacer()
                    Text("\(model.galleryIndex + 1) / \(tiles.count)")
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(WisentDesign.secondary)
                    Button("‹") { model.stepGallery(-1, count: tiles.count) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button("›") { model.stepGallery(1, count: tiles.count) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                focusedAsset(tiles: tiles)
                filmstrip(tiles: tiles)
            }
        }
        .onAppear { model.focusLaunchedAsset() }
    }

    @ViewBuilder
    private func focusedAsset(tiles: [URL]) -> some View {
        if let url = model.currentGalleryAsset(tiles: tiles) {
            tileContent(url)
                .frame(maxHeight: 380)
                .frame(maxWidth: .infinity)
                .background(WisentDesign.muted.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: WisentDesign.Space.x3) {
                Text(url.lastPathComponent)
                    .font(WisentTypeScale.bodyStrong())
                    .foregroundStyle(WisentDesign.ink)
                Spacer(minLength: 0)
                if url.pathExtension.lowercased() == "glb" {
                    Button("Animate this") { model.selectedGLB = url }
                }
                Button("Reveal in Finder") { model.revealInFinder(url) }
            }
        }
    }

    private func filmstrip(tiles: [URL]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WisentDesign.Space.x2) {
                    ForEach(Array(tiles.enumerated()), id: \.element) { index, url in
                        ZStack {
                            Rectangle().fill(WisentDesign.muted.opacity(0.10))
                            tileContent(url)
                                .padding(4)
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(index == model.galleryIndex ? WisentDesign.brand : .clear, lineWidth: 2)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { model.galleryIndex = index }
                        .id(index)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 96)
            .onChange(of: model.galleryIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func tileContent(_ url: URL) -> some View {
        switch url.pathExtension.lowercased() {
        case "gif":
            AnimatedGifPlayer(url: url)
                .aspectRatio(contentMode: .fit)
        case "png":
            imageOrPlaceholder(url)
        default:
            if let preview = matchedPreview(for: url) {
                imageOrPlaceholder(preview)
            } else {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 40))
                    .foregroundStyle(WisentDesign.muted)
            }
        }
    }

    @ViewBuilder
    private func imageOrPlaceholder(_ url: URL) -> some View {
        if url.pathExtension.lowercased() == "gif" {
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

    private var placeholder: some View {
        Image(systemName: "cube.transparent")
    }

    /// A .glb tile shows the rendered sibling the pipeline already produced
    /// (smok.glb → smok-flap-preview.gif, kamien.glb → kamien-preview.png).
    private func matchedPreview(for glbURL: URL) -> URL? {
        let stem = glbURL.deletingPathExtension().lastPathComponent
        return model.assetFiles.first { candidate in
            candidate.deletingLastPathComponent() == glbURL.deletingLastPathComponent()
                && candidate != glbURL
                && ["png", "gif"].contains(candidate.pathExtension.lowercased())
                && candidate.deletingPathExtension().lastPathComponent.hasPrefix(stem)
        }
    }

    private func tileTapped(_ url: URL) {
        if url.pathExtension.lowercased() == "glb" {
            model.selectedGLB = url
            if let preview = matchedPreview(for: url) {
                model.animatedPreviewURL = preview
            }
        }
    }

    /// The animation workflow for one selected .glb: the operator names a
    /// clip (or leaves empty for the longest), Glina renders it through
    /// Blender, and the looping GIF plays right below.
    /// Two independent entries: "Animate" on a .glb opens the render form,
    /// "Play" on a .gif plays it. Either may exist without the other.
    @ViewBuilder
    private var animationSection: some View {
        if model.selectedGLB != nil || model.animatedPreviewURL != nil {
            WisentSectionBox(
                title: "Animation preview",
                detail: "Blender renders the clip; the looping GIF plays here."
            ) {
                if let glb = model.selectedGLB {
                    Text(glb.lastPathComponent)
                        .font(WisentTypeScale.identifier())
                    HStack(spacing: WisentDesign.Space.x3) {
                        TextField("clip (empty = longest)", text: $model.animationClip)
                            .font(WisentTypeScale.identifier())
                            .frame(maxWidth: 240)
                        Button(model.isRenderingAnimation ? "Rendering…" : "Render animation") {
                            Task { await model.renderAnimationPreview(for: glb) }
                        }
                        .disabled(model.isRenderingAnimation)
                    }
                }
                if let note = model.animationNote, !note.isEmpty {
                    Text(note)
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(WisentDesign.secondary)
                }
                if let gif = model.animatedPreviewURL {
                    AnimatedGifPlayer(url: gif)
                        .frame(maxWidth: 420, maxHeight: 320)
                        .frame(maxWidth: .infinity, alignment: .center)
                    HStack {
                        Spacer()
                        Button("Close preview") { model.animatedPreviewURL = nil }
                    }
                }
            }
        }
    }

}
/// Frame-driven GIF player. AppKit's `NSImageView.animates` proved unreliable
/// for these generated files, so this view decodes every frame with ImageIO
/// and advances it explicitly on the main run loop.
struct AnimatedGifPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> FrameDrivenGIFView {
        let view = FrameDrivenGIFView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.load(url)
        return view
    }

    func updateNSView(_ view: FrameDrivenGIFView, context: Context) {
        if view.needsReload(for: url) { view.load(url) }
    }

    static func dismantleNSView(_ view: FrameDrivenGIFView, coordinator: Void) {
        view.stop()
    }
}

@MainActor
final class FrameDrivenGIFView: NSImageView {
    private var frames: [NSImage] = []
    private var delays: [TimeInterval] = []
    private var frameIndex = 0
    private var animationTask: Task<Void, Never>?
    private(set) var loadedURL: URL?
    private var loadedModificationDate: Date?
    private var nextReloadCheck = Date.distantPast

    func needsReload(for url: URL) -> Bool {
        loadedURL != url || modificationDate(for: url) != loadedModificationDate
    }

    func load(_ url: URL) {
        stop()
        loadedURL = url
        loadedModificationDate = modificationDate(for: url)
        nextReloadCheck = Date().addingTimeInterval(1)
        frames = []
        delays = []
        frameIndex = 0
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            image = nil
            return
        }
        for index in 0..<CGImageSourceGetCount(source) {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, options) else { continue }
            frames.append(NSImage(cgImage: cgImage, size: .zero))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let rawDelay =
                (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
            delays.append(max(rawDelay, 0.02))
        }
        guard !frames.isEmpty else {
            image = nil
            return
        }
        image = frames[frameIndex]
        if frames.count > 1 { startAnimation() }
    }

    func stop() {
        animationTask?.cancel()
        animationTask = nil
    }

    private func startAnimation() {
        stop()
        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.frames.count > 1 {
                let delay = self.delays.indices.contains(self.frameIndex) ? self.delays[self.frameIndex] : 0.1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if Date() >= self.nextReloadCheck {
                    self.nextReloadCheck = Date().addingTimeInterval(1)
                    if let url = self.loadedURL, self.needsReload(for: url) {
                        self.load(url)
                        return
                    }
                }
                self.frameIndex = (self.frameIndex + 1) % self.frames.count
                self.image = self.frames[self.frameIndex]
                self.needsDisplay = true
                self.displayIfNeeded()
            }
        }
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
