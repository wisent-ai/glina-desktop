// The animation preview. The app never renders glTF itself: the backend
// walks the same Blender bridge every other workflow does and hands back a
// looping GIF, which is what the window shows.

import Foundation

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

    static func tail(_ text: String, maxCharacters: Int = 400) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        return "…" + trimmed.suffix(maxCharacters)
    }
}
}
