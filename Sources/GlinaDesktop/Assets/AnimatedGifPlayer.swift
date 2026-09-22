// Playing a generated animation. AppKit NSImageView.animates proved
// unreliable for these files, so every frame is decoded with ImageIO and
// advanced explicitly on the main run loop.

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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
    /// A frame without a delay shows for a tenth of a second; browsers clamp anything shorter than 20 ms.
    private static let defaultFrameDelay: TimeInterval = 0.1
    private static let minimumFrameDelay: TimeInterval = 0.02
    private static let nanosecondsPerSecond: Double = 1_000_000_000

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
                ?? Self.defaultFrameDelay
            delays.append(max(rawDelay, Self.minimumFrameDelay))
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
                let delay = self.delays.indices.contains(self.frameIndex) ? self.delays[self.frameIndex] : Self.defaultFrameDelay
                try? await Task.sleep(nanoseconds: UInt64(delay * Self.nanosecondsPerSecond))
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
