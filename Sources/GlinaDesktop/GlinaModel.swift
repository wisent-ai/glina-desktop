import Foundation
import Quartz
import SwiftUI

@MainActor
final class GlinaModel: ObservableObject {

    @Published var draft = GlinaCommandDraft()
    @Published private(set) var isRunning = false
    @Published private(set) var result: GlinaCommandResult?
    @Published private(set) var failure: String?
    @Published private(set) var startedAt: Date?
    /// Live combined stdout/stderr, in the process's own order.
    @Published private(set) var liveLog = ""
    @Published private(set) var outputPaths: [String] = []

    // Assets browser.
    @Published var assetsDirectory: URL?
    @Published private(set) var assetFiles: [URL] = []

    /// Strongly retained Quick Look controller — QLPreviewPanel's dataSource
    /// is assigned, not retained, so something must own it.
    @Published var previewController: AssetPreviewController?

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
    /// `Glina --assets-dir PATH` opens straight onto an output directory.
    init(assetsDirectory: URL? = nil) {
        self.assetsDirectory = assetsDirectory
        refreshAssets()
    }


    private let runner = GlinaCommandRunner()
    private var pendingChunks: [Int: String] = [:]
    private var nextSequence = 1

    var output: String {
        guard let result else { return "" }
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func select(_ action: GlinaAction) {
        draft.action = action
        result = nil
        failure = nil
        liveLog = ""
        outputPaths = []
    }

    func run() async {
        guard !isRunning else { return }
        if let problem = draft.validationProblem {
            failure = problem
            return
        }
        isRunning = true
        result = nil
        failure = nil
        liveLog = ""
        outputPaths = []
        pendingChunks = [:]
        nextSequence = 1
        startedAt = Date()
        defer { isRunning = false }
        do {
            let arguments = draft.arguments
            let result = try await runner.run(arguments: arguments) { [weak self] order, chunk in
                Task { @MainActor [weak self] in self?.appendChunk(order, chunk) }
            }
            self.result = result
            liveLog = combined(result)
            outputPaths = Self.extractPaths(from: result.standardOutput, action: draft.action)
            if result.status != 0 {
                let sentence = result.standardError
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                failure = sentence.isEmpty
                    ? "Glina exited with status \(result.status)."
                    : sentence
            }
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The exact command of the last completed run — what actually executed,
    /// not a preview that could still be edited.
    func appendChunk(_ order: Int, _ chunk: String) {
        pendingChunks[order] = chunk
        while let next = pendingChunks.removeValue(forKey: nextSequence) {
            liveLog += next
            nextSequence += 1
        }
    }

    private func combined(_ result: GlinaCommandResult) -> String {
        let stdout = result.standardOutput
        let stderr = result.standardError
        return stdout + stderr
    }

    /// Sculpt and verify print one JSON document; surface the artifact paths
    /// it names so the operator can go straight to Finder or Quick Look.
    static func extractPaths(from standardOutput: String, action: GlinaAction) -> [String] {
        guard action == .sculpt || action == .verify,
              let data = standardOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any]
        else { return [] }
        var paths: [String] = []
        for key in ["outPath", "file", "path"] {
            if let value = object[key] as? String { paths.append(value) }
        }
        return paths
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
        refreshAssets()
    }

    func refreshAssets() {
        guard let root = assetsDirectory else {
            assetFiles = []
            return
        }
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            assetFiles = []
            return
        }
        var found: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ["glb", "png", "gif"].contains(ext) else { continue }
            found.append(url)
        }
        assetFiles = found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Animation preview
    //
    // The app never renders glTF itself: `glina preview-anim` walks the same
    // Blender MCP bridge as every other command and hands back a looping GIF,
    // which NSImageView plays inline.

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
        var arguments = ["preview-anim", glbURL.path]
        let clip = animationClip.trimmingCharacters(in: .whitespaces)
        if !clip.isEmpty { arguments += ["--clip", clip] }
        do {
            let result = try await runner.run(arguments: arguments) { _, _ in }
            guard result.status == 0 else {
                animationNote = Self.tail(result.standardError.isEmpty ? result.standardOutput : result.standardError)
                return
            }
            if let data = result.standardOutput.data(using: .utf8),
               let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let outPath = doc["outPath"] as? String {
                animatedPreviewURL = URL(fileURLWithPath: outPath)
                refreshAssets()
                animationNote = "rendered " + outPath
            } else {
                animationNote = Self.tail(result.standardOutput)
            }
        } catch {
            animationNote = error.localizedDescription
        }
    }

    private static func tail(_ text: String, maxCharacters: Int = 400) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        return "…" + trimmed.suffix(maxCharacters)
    }
}
