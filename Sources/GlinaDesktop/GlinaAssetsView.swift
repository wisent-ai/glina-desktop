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
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("Choose Directory") { model.chooseAssetsDirectory() }
                    if model.assetsDirectory != nil {
                        Button("Refresh") { model.refreshAssets() }
                    }
                }
            }

            if let root = model.assetsDirectory {
                commandNote("find \(root.path) -name '*.glb' -o -name '*.png' -o -name '*.gif'")
                assetsList
                animationSection
            } else {
                WisentEmptyPanel(
                    title: "No output directory",
                    detail: "Choose the directory the glina CLI sculpts into, then browse what it produced.",
                    symbol: "cube.transparent"
                )
            }
        }
    }
    private func presentPreview(urls: [URL], index: Int) {
        model.presentPreview(urls: urls, index: index)
    }

    /// Browsing is app-local; the only external process here is Finder.
    private func commandNote(_ line: String) -> some View {
        WisentSectionBox(title: "Command", detail: "The exact listing this view mirrors.") {
            Text(line)
                .font(WisentTypeScale.identifier())
                .foregroundStyle(WisentDesign.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assetsList: some View {
        let models = model.assetFiles.filter { $0.pathExtension.lowercased() == "glb" }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let groupedStems = Set(models.map { $0.deletingPathExtension().lastPathComponent })
        let orphans = model.assetFiles
            .filter { $0.pathExtension.lowercased() != "glb" }
            .filter { preview in !groupedStems.contains { stem in preview.deletingPathExtension().lastPathComponent.hasPrefix(stem) } }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let tiles = models + orphans
        return WisentSectionBox(title: "Gallery", detail: "\(models.count) asset(s)\(orphans.isEmpty ? "" : ", +\(orphans.count) render(s)"). GIF tiles play by themselves; click a model to animate it.") {
            if tiles.isEmpty {
                Text("No assets under this directory yet.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 170), spacing: WisentDesign.Space.x3)],
                        spacing: WisentDesign.Space.x3
                    ) {
                        ForEach(tiles, id: \.self) { url in
                            assetTile(url)
                        }
                    }
                    .padding(.vertical, WisentDesign.Space.x1)
                }
                .frame(maxHeight: 520)
            }
        }
    }

    private func assetTile(_ url: URL) -> some View {
        VStack(spacing: 6) {
            ZStack {
                WisentDesign.muted.opacity(0.10)
                tileContent(url)
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onTapGesture { tileTapped(url) }
            Text(url.lastPathComponent)
                .font(WisentTypeScale.caption())
                .foregroundStyle(WisentDesign.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    /// clip (or leaves empty for the CLI's longest), the glina CLI renders
    /// through Blender, and the looping GIF plays right below.
    /// Two independent entries: "Animate" on a .glb opens the render form,
    /// "Play" on a .gif plays it. Either may exist without the other.
    @ViewBuilder
    private var animationSection: some View {
        if model.selectedGLB != nil || model.animatedPreviewURL != nil {
            WisentSectionBox(
                title: "Animation preview",
                detail: "Runs `glina preview-anim` — Blender renders the clip, this window plays it."
            ) {
                if let glb = model.selectedGLB {
                    Text(glb.lastPathComponent)
                        .font(WisentTypeScale.identifier())
                        .textSelection(.enabled)
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
                        .textSelection(.enabled)
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
/// NSImageView plays animated GIF representations out of the box; SwiftUI has
/// no native equivalent, so this is the whole bridge.
struct AnimatedGifPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = NSImage(contentsOf: url)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = NSImage(contentsOf: url)
    }
}
