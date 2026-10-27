// Playing a generated animation. AppKit NSImageView.animates proved
// unreliable for these files, so every frame is decoded with ImageIO and
// played by Core Animation at the delays the file states.

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Frame-driven GIF player. AppKit's `NSImageView.animates` proved unreliable
/// for these generated files, so this view decodes every frame with ImageIO
/// and hands the frames to a discrete Core Animation keyframe animation timed
/// by the file's own delays. The view follows its file: a watch on it loads
/// the animation again when the backend rewrites or replaces the file, so a
/// new render shows without the view checking on a clock.
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

/// Why a GIF is shown as a warning instead of played.
struct GIFLoadFailure: LocalizedError {
    let path: String
    let reason: String

    var errorDescription: String? {
        "Glina cannot play \(path): \(reason)."
    }
}

@MainActor
final class FrameDrivenGIFView: NSImageView {
    private var animationLayer: CALayer?
    private var fileWatch: DispatchSourceFileSystemObject?
    private(set) var loadedURL: URL?
    /// The last load failed; the next update of the view tries again.
    private var failed = false

    func needsReload(for url: URL) -> Bool {
        loadedURL != url || failed
    }

    func load(_ url: URL) {
        stop()
        loadedURL = url
        switch Result(catching: { try Self.decode(url) }) {
        case .success(let decoded):
            failed = false
            toolTip = nil
            show(decoded.frames, delays: decoded.delays)
        case .failure(let error):
            show(failure: error.localizedDescription)
        }
        watch(url)
    }

    func stop() {
        animationLayer?.removeFromSuperlayer()
        animationLayer = nil
        fileWatch?.cancel()
        fileWatch = nil
    }

    override func layout() {
        super.layout()
        animationLayer?.frame = bounds
    }

    /// Plays the frames when every frame states a delay and the delays add
    /// up to some time. Otherwise the file is shown as its first frame rather
    /// than played at a speed this view invented.
    private func show(_ frames: [CGImage], delays: [TimeInterval]?) {
        let first = NSImage(cgImage: frames[frames.startIndex], size: .zero)
        guard let delays, !frames.dropFirst().isEmpty else {
            image = first
            return
        }
        let total: TimeInterval = delays.reduce(.zero, +)
        guard total > .zero else {
            image = first
            return
        }
        // Discrete keyframes start each frame at its share of the loop and
        // end the loop at the last entry, one more than there are frames.
        var starts: [NSNumber] = []
        var elapsed: TimeInterval = .zero
        for delay in delays {
            starts.append(NSNumber(value: elapsed / total))
            elapsed += delay
        }
        starts.append(NSNumber(value: elapsed / total))
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = starts
        animation.duration = total
        animation.calculationMode = .discrete
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        wantsLayer = true
        image = nil
        let player = CALayer()
        player.frame = bounds
        player.contentsGravity = .resizeAspect
        player.contents = frames[frames.startIndex]
        player.add(animation, forKey: "frames")
        layer?.addSublayer(player)
        animationLayer = player
    }

    private func show(failure sentence: String) {
        failed = true
        toolTip = sentence
        image = NSImage(
            systemSymbolName: "exclamationmark.triangle", accessibilityDescription: sentence)
    }

    /// Watches the loaded file for the backend rewriting it in place or
    /// renaming a finished file over it. Either loads the file again, which
    /// opens a new watch on whatever file then has the name.
    private func watch(_ url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= .zero else {
            let reason = String(cString: strerror(errno))
            show(failure: "Glina cannot follow \(url.path) for new renders: \(reason).")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadLoadedFile() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileWatch = source
    }

    private func reloadLoadedFile() {
        guard let loadedURL else { return }
        load(loadedURL)
    }

    /// Every frame of the file and, when every frame states one, each frame's
    /// delay. ImageIO's delay is the file's own, with the same floor every GIF
    /// decoder applies to delays too short to honour.
    private static func decode(_ url: URL) throws -> (frames: [CGImage], delays: [TimeInterval]?) {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw GIFLoadFailure(path: url.path, reason: "ImageIO cannot open it as an image")
        }
        var frames: [CGImage] = []
        var delays: [TimeInterval] = []
        for index in .zero..<CGImageSourceGetCount(source) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, options) else {
                throw GIFLoadFailure(path: url.path, reason: "ImageIO cannot decode frame \(index)")
            }
            frames.append(frame)
            let properties =
                CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            if let delay = gif?[kCGImagePropertyGIFDelayTime] as? Double {
                delays.append(delay)
            }
        }
        guard !frames.isEmpty else {
            throw GIFLoadFailure(path: url.path, reason: "it holds no frames")
        }
        guard delays.count == frames.count else { return (frames, nil) }
        return (frames, delays)
    }
}
