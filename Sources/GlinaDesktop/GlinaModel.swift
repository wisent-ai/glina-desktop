import Foundation
import Quartz
import SwiftUI
import WisentErrors

enum GallerySort: String, CaseIterable, Identifiable {
    case nameAscending, nameDescending, newestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nameAscending: return "Name A→Z"
        case .nameDescending: return "Name Z→A"
        case .newestFirst: return "Newest first"
        }
    }
}
private struct AssetSnapshot: Hashable {
    let path: String
    let size: Int
    let modificationDate: Date
}


@MainActor
final class GlinaModel: ObservableObject {
    @Published var draft = GlinaCommandDraft()
    @Published private(set) var isRunning = false
    @Published private(set) var result: GlinaOutcome?
    @Published private(set) var failure: String?
    @Published private(set) var startedAt: Date?
    /// Live log streamed by the backend, in the backend's own order.
    @Published private(set) var liveLog = ""
    /// The last failure came from starting the backend itself, so the panel
    /// offers a Retry.
    @Published private(set) var backendStartFailed = false
    @Published private(set) var outputPaths: [String] = []
    @Published private(set) var assetImport: GlinaAssetImport?
    @Published private(set) var importedAssetPath: String?

    // Assets browser.
    @Published var assetsDirectory: URL?
    @Published private(set) var assetFiles: [URL] = []
    private var assetSnapshot: [AssetSnapshot] = []
    private var assetRefreshTask: Task<Void, Never>?

    /// Strongly retained Quick Look controller — QLPreviewPanel's dataSource
    /// is assigned, not retained, so something must own it.
    @Published var previewController: AssetPreviewController?

    // Gallery browsing: one focused element, arrows/strip to move, sort order.
    @Published var gallerySort: GallerySort = .nameAscending
    @Published var galleryIndex = 0
    @Published var focusPath: String?

    /// `Glina --assets-dir PATH` opens straight onto an output directory.
    init(assetsDirectory: URL? = nil) {
        self.assetsDirectory = assetsDirectory
        refreshAssets()
        startAutomaticAssetRefresh()
    }

    deinit {
        assetRefreshTask?.cancel()
    }

    private let backend = GlinaBackendProcess()

    /// Launch flags: `--assets-dir PATH` selects the output directory,
    /// `--play PATH` opens the window already on that element.
    func applyLaunchOptions() {
        let arguments = ProcessInfo.processInfo.arguments
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--assets-dir" where arguments.indices.contains(index + 1):
                setAssetsDirectory(URL(fileURLWithPath: arguments[index + 1]))
            case "--play" where arguments.indices.contains(index + 1):
                let url = URL(fileURLWithPath: arguments[index + 1])
                if FileManager.default.fileExists(atPath: url.path) {
                    focusPath = url.path
                }
                draft.action = .assets
            default:
                break
            }
            index += 1
        }
    }

    var output: String {
        result?.document ?? ""
    }


    func select(_ action: GlinaAction) {
        draft.action = action
        result = nil
        failure = nil
        backendStartFailed = false
        liveLog = ""
        outputPaths = []
    }

    func run() async {
        guard !isRunning else { return }
        if let problem = draft.validationProblem {
            failure = problem
            backendStartFailed = false
            WisentFailureReporter.shared.report(
                failurePoint: "glina.run",
                code: "unknown",
                service: "glina",
                detail: problem
            )
            return
        }
        isRunning = true
        result = nil
        failure = nil
        backendStartFailed = false
        liveLog = ""
        outputPaths = []
        startedAt = Date()
        defer { isRunning = false }
        do {
            let client = try await makeClient()
            let outcome: GlinaOutcome
            switch draft.action {
            case .sculpt:
                outcome = try await client.sculpt(prompt: draft.prompt, rounds: draft.rounds, onLog: appendLog)
            case .verify:
                outcome = try await client.verify(path: draft.assetPath, onLog: appendLog)
            case .config:
                outcome = try await client.config()
            case .blenderHealth:
                outcome = try await client.blenderHealth()
            case .welesTools:
                outcome = try await client.welesTools()
            case .assets:
                return
            }
            result = outcome
            outputPaths = outcome.paths
            failure = outcome.refusal
            if let refusal = outcome.refusal {
                WisentFailureReporter.shared.report(
                    failurePoint: "glina.run",
                    code: "unknown",
                    service: "glina",
                    detail: refusal
                )
            }
        } catch let error as GlinaBackendError {
            backendStartFailed = true
            failure = error.errorDescription
            WisentFailureReporter.shared.report(
                failurePoint: "glina.backend_start",
                code: "infra_down",
                service: "glina",
                detail: error.errorDescription
            )
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            WisentFailureReporter.shared.report(
                failurePoint: "glina.run",
                code: "unknown",
                service: "glina",
                detail: failure
            )
        }
    }

    func importAsset(from source: URL) async {
        guard !isRunning else { return }
        isRunning = true
        result = nil
        failure = nil
        assetImport = nil
        importedAssetPath = nil
        backendStartFailed = false
        liveLog = ""
        outputPaths = []
        startedAt = Date()
        defer { isRunning = false }
        do {
            let client = try await makeClient()
            let outcome = try await client.importAsset(source: source.path, onLog: appendLog)
            result = outcome
            outputPaths = outcome.paths
            guard outcome.status == 0,
                  let data = outcome.document.data(using: .utf8),
                  let report = try? JSONDecoder().decode(GlinaAssetImport.self, from: data)
            else {
                failure = outcome.refusal ?? "Glina returned an unreadable workspace import result."
                return
            }
            assetImport = report
            guard report.accepted, let destination = report.path else {
                failure = report.reason ?? "Glina did not accept this asset."
                return
            }
            let url = URL(fileURLWithPath: destination)
            setAssetsDirectory(url.deletingLastPathComponent())
            selectedGLB = url
            draft.assetPath = destination
            draft.action = .assets
            outputPaths = [destination]
            importedAssetPath = destination
        } catch let error as GlinaBackendError {
            backendStartFailed = true
            failure = error.errorDescription
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func makeClient() async throws -> GlinaClient {
        GlinaClient(baseURL: try await backend.endpoint())
    }

    /// Appends one streamed log event; NDJSON already arrives in the
    /// backend's own order, so no resequencing is needed.
    private func appendLog(_ chunk: String) {
        liveLog += chunk
    }

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

    private func modificationDate(_ url: URL) -> Date {
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

    private func startAutomaticAssetRefresh() {
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

    // MARK: - Animation preview
    //
    // The app never renders glTF itself: the backend walks the same Blender
    // MCP bridge as every other workflow and hands back a looping GIF, which
    // NSImageView plays inline.

    @Published var animationClip = ""
    @Published private(set) var isRenderingAnimation = false
    @Published private(set) var animationNote: String?
    @Published var animatedPreviewURL: URL?
    @Published var selectedGLB: URL?

    func renderAnimationPreview(for glbURL: URL) async {
        guard !isRenderingAnimation else { return }
        isRenderingAnimation = true
        animationNote = nil
        defer { isRenderingAnimation = false }
        let clip = animationClip.trimmingCharacters(in: .whitespaces)
        do {
            let client = try await makeClient()
            let outcome = try await client.previewAnim(path: glbURL.path, clip: clip) { _ in }
            guard outcome.status == 0, outcome.refusal == nil else {
                animationNote = Self.tail(outcome.refusal ?? "The render did not finish.")
                WisentFailureReporter.shared.report(
                    failurePoint: "glina.animation_preview",
                    code: "unknown",
                    service: "glina",
                    detail: animationNote
                )
                return
            }
            if let outPath = outcome.paths.first {
                animatedPreviewURL = URL(fileURLWithPath: outPath)
                refreshAssets()
                animationNote = "rendered " + outPath
            } else {
                animationNote = Self.tail(outcome.document)
            }
        } catch {
            animationNote = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            WisentFailureReporter.shared.report(
                failurePoint: "glina.animation_preview",
                code: error is GlinaBackendError ? "infra_down" : "unknown",
                service: "glina",
                detail: animationNote
            )
        }
    }

    private static func tail(_ text: String, maxCharacters: Int = 400) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        return "…" + trimmed.suffix(maxCharacters)
    }
}
