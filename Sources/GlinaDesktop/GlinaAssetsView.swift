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
                commandNote("find \(root.path) -name '*.glb' -o -name '*.png'")
                assetsList
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
                Text("No .glb or .png files under this directory yet.")
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
            Image(systemName: url.pathExtension.lowercased() == "glb" ? "cube" : "photo")
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
            Button("Quick Look") { preview() }
            Button("Reveal in Finder") { model.revealInFinder(url) }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { preview() }
        .padding(.vertical, WisentDesign.Space.x1)
    }
}
