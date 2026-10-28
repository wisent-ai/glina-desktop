import ImageIO
import Quartz
import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

/// Quick Look over the produced artifacts. The panel is driven directly —
/// the data source is installed before the panel is keyed, so no responder
/// in the chain has to opt in first.
@MainActor
final class AssetPreviewController: NSObject, @preconcurrency QLPreviewPanelDataSource,
    @preconcurrency QLPreviewPanelDelegate
{
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
                detail:
                    "Where Glina writes sculpted assets. The browser lists every model, still and animation beneath it."
            ) {
                HStack(spacing: WisentDesign.Space.x3) {
                    directoryLabel
                    TextField("Variant of base id (optional)", text: $model.variantParent)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: WisentAppLayout.sidebarWidth)
                    Spacer(minLength: .zero)
                    Button("Import GLB…") { chooseAssetForImport() }
                        .disabled(model.isRunning)
                    Button("Choose Directory") { model.chooseAssetsDirectory() }
                    if model.assetsDirectory != nil {
                        Button("Refresh") { model.refreshAssets() }
                    }
                }
                if let imported = model.assetImport {
                    Text(importLine(imported))
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(imported.accepted ? WisentDesign.success : WisentDesign.danger)
                }
            }

            if let failure = model.assetsListingFailure {
                WisentAlertPanel(
                    tone: .danger,
                    title: "The directory could not be listed",
                    detail: failure,
                    actions: [WisentAction("Refresh", symbol: "arrow.clockwise") { model.refreshAssets() }]
                )
            }
            if let failure = model.assetsWatchFailure {
                WisentAlertPanel(
                    tone: .warning,
                    title: "The directory is not watched for changes",
                    detail: "\(failure) The list changes only when you refresh it.",
                    actions: [WisentAction("Watch again", symbol: "eye") { model.watchAssets() }]
                )
            }

            if model.assetsDirectory != nil {
                assetsList
                animationSection
            } else {
                WisentEmptyPanel(
                    title: "No output directory",
                    detail:
                        "Choose the folder your sculpted assets are saved in, then browse what Glina produced.",
                    symbol: "cube.transparent"
                )
            }
        }
    }

    /// The open directory's whole path, wrapped rather than cut, so the
    /// operator can read and select every part of it.
    @ViewBuilder
    private var directoryLabel: some View {
        if let directory = model.assetsDirectory {
            Text(directory.path)
                .font(WisentTypeScale.identifier())
                .foregroundStyle(WisentDesign.ink)
                .textSelection(.enabled)
        } else {
            Text("No directory chosen")
                .font(WisentTypeScale.identifier())
                .foregroundStyle(WisentDesign.muted)
        }
    }

    /// What the backend did with an imported asset: where it kept it, or why
    /// it kept nothing, in the backend's own words when it gave some.
    private func importLine(_ imported: GlinaAssetImport) -> String {
        let status = imported.status.capitalized
        switch (imported.path, imported.reason) {
        case let (.some(path), _):
            return "\(status): \(path)"
        case let (.none, .some(reason)):
            return "\(status): \(reason)"
        case (.none, .none):
            return "\(status): the backend kept no file and gave no reason."
        }
    }

    private func chooseAssetForImport() {
        guard !model.isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // The system derives the model type from its name; on a system that
        // derives none, the panel offers every file and the backend's import
        // gate refuses one that is not a model.
        if let modelType = AssetKind.modelType {
            panel.allowedContentTypes = [modelType]
        }
        panel.message = "Choose a GLB for Glina to validate and keep in its workspace."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await model.importAsset(
                from: url,
                variantOf: model.variantParent.isEmpty ? nil : model.variantParent
            )
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
                    .frame(maxWidth: WisentAppLayout.facetRailWidth)
                    Spacer()
                    Text("\(model.galleryPosition(tiles: tiles)) / \(tiles.count)")
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(WisentDesign.secondary)
                    Button("‹") { model.showPreviousTile(of: tiles) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button("›") { model.showNextTile(of: tiles) }
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
                .frame(maxHeight: AssetsLayout.previewHeight)
                .frame(maxWidth: .infinity)
                .background(WisentDesign.canvasMuted)
                .clipShape(RoundedRectangle(cornerRadius: WisentDesign.Radius.medium))
            HStack(spacing: WisentDesign.Space.x3) {
                Text(url.lastPathComponent)
                    .font(WisentTypeScale.bodyStrong())
                    .foregroundStyle(WisentDesign.ink)
                Spacer(minLength: .zero)
                if model.assetKind(of: url) == .model {
                    Button("Animate this") { model.selectedGLB = url }
                    Button(model.isRenderingScene ? "Rendering scene…" : "Preview in scene") {
                        Task { await model.renderScenePreview(for: url) }
                    }
                    .disabled(model.isRenderingScene)
                }
                Button("Reveal in Finder") { model.revealInFinder(url) }
            }
            if model.sceneSourcePath == url.path {
                if let note = model.sceneNote {
                    Text(note).font(WisentTypeScale.caption())
                        .foregroundStyle(
                            model.scenePreviewImage == nil
                                ? WisentDesign.danger : WisentDesign.secondary)
                }
                if let image = model.scenePreviewImage {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxHeight: AssetsLayout.previewHeight)
                }
            }
        }
    }

    /// The animation workflow for one selected model: the operator names a
    /// clip (or leaves empty for the longest), Glina renders it through
    /// Blender, and the looping GIF plays right below.
    /// Two independent entries: "Animate" on a model opens the render form,
    /// "Play" on an animation plays it. Either may exist without the other.
    @ViewBuilder
    private var animationSection: some View {
        if model.selectedGLB != nil || model.animatedPreviewURL != nil {
            WisentSectionBox(
                title: "Animation preview",
                detail: nil
            ) {
                if let glb = model.selectedGLB {
                    Text(glb.lastPathComponent)
                        .font(WisentTypeScale.identifier())
                    HStack(spacing: WisentDesign.Space.x3) {
                        TextField("clip (empty = longest)", text: $model.animationClip)
                            .font(WisentTypeScale.identifier())
                            .frame(maxWidth: WisentAppLayout.sidebarWidth)
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
                        .frame(maxWidth: WisentAppLayout.dialogWidth, maxHeight: AssetsLayout.previewHeight)
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
