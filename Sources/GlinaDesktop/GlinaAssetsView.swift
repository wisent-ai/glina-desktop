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
        let urls = model.assetFiles
        return WisentSectionBox(title: "Artifacts", detail: "\(urls.count) file(s). Double-click to Quick Look.") {
            if urls.isEmpty {
                Text("No .glb, .png or .gif files under this directory yet.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
            } else {
                ScrollView {
                    VStack(spacing: WisentDesign.Space.x1) {
                        ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                            assetRow(url) { presentPreview(urls: urls, index: index) }
                            if index < urls.count - 1 { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
    }

    private func assetRow(_ url: URL, preview: @escaping () -> Void) -> some View {
        HStack(spacing: WisentDesign.Space.x3) {
            Image(systemName: Self.icon(for: url))
                .foregroundStyle(WisentDesign.brand)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(WisentTypeScale.bodyStrong())
                    .foregroundStyle(WisentDesign.ink)
                Text(url.deletingLastPathComponent().path)
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if url.pathExtension.lowercased() == "glb" {
                Button("Animate") { model.selectedGLB = url }
            }
            if url.pathExtension.lowercased() == "gif" {
                Button("Play") { model.animatedPreviewURL = url }
            }
            Button("Quick Look") { preview() }
            Button("Reveal in Finder") { model.revealInFinder(url) }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { preview() }
        .padding(.vertical, WisentDesign.Space.x1)
    }

    private static func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "glb": return "cube"
        case "gif": return "play.rectangle"
        default: return "photo"
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
