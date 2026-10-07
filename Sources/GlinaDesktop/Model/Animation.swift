// The animation preview. The app never renders glTF itself: the backend
// walks the same Blender bridge every other workflow does and hands back a
// looping GIF, which is what the window shows.

import AppKit
import Foundation
import WisentErrors

extension GlinaModel {

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
                animationNote = (outcome.refusal ?? "The render did not finish.")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
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
                animationNote = outcome.document.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            animationNote =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            WisentFailureReporter.shared.report(
                failurePoint: "glina.animation_preview",
                code: error is GlinaBackendError ? "infra_down" : "unknown",
                service: "glina",
                detail: animationNote
            )
        }
    }

    func renderScenePreview(for glbURL: URL) async {
        guard !isRenderingScene else { return }
        isRenderingScene = true
        sceneSourcePath = glbURL.path
        scenePreviewImage = nil
        sceneNote = nil
        defer {
            isRenderingScene = false
            if scenePreviewImage == nil, let sceneNote {
                WisentFailureReporter.shared.report(
                    failurePoint: "glina.scene_preview",
                    code: "unknown",
                    service: "glina",
                    detail: sceneNote
                )
            }
        }
        do {
            let client = try await makeClient()
            let outcome = try await client.previewScene(path: glbURL.path) { _ in }
            guard outcome.status == 0, outcome.refusal == nil else {
                sceneNote = (outcome.refusal ?? "The scene render did not finish.")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
            guard let outPath = outcome.paths.first else {
                sceneNote =
                    "Glina reported a scene preview without an image path: \(outcome.document)"
                return
            }
            let imageURL = URL(fileURLWithPath: outPath)
            guard let image = NSImage(contentsOf: imageURL), image.isValid else {
                sceneNote =
                    "Glina reported a scene preview that could not be opened as an image: \(outPath)"
                return
            }
            scenePreviewImage = image
            sceneNote = "Rendered \(outPath)"
            refreshAssets()
        } catch {
            sceneNote = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

}
