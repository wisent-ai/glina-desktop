import CoreServices
import Foundation

/// Every change anywhere under the assets directory, delivered on the main
/// queue as it happens, so the browser lists the tree after the backend
/// writes into it instead of on a clock.
///
/// FSEvents is used rather than a vnode watch because the backend writes into
/// subdirectories and rewrites files in place, and a vnode watch on the root
/// sees neither. FSEvents follows paths, not open descriptors, so a root that
/// does not exist yet is still watched and its creation is reported. The
/// stream is asked for no latency, so nothing here waits an interval anybody
/// chose; changes that land while the main queue is busy arrive as one batch.
final class AssetTreeWatch {
    struct Failure: LocalizedError {
        enum Step: String {
            case create, start
        }

        let path: String
        let step: Step

        var errorDescription: String? {
            "FSEvents refused to \(step.rawValue) a stream over \(path), so the assets list does not follow the backend's writes. Choose the directory again to retry."
        }
    }

    private final class Handler {
        let onChange: @MainActor () -> Void

        init(_ onChange: @escaping @MainActor () -> Void) {
            self.onChange = onChange
        }
    }

    private let stream: FSEventStreamRef
    private let handler: Handler

    init(root: URL, onChange: @escaping @MainActor () -> Void) throws {
        let handler = Handler(onChange)
        var context = FSEventStreamContext(
            version: .zero,
            info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let handler = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { handler.onChange() }
        }
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                [root.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                .zero,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagFileEvents
                        | kFSEventStreamCreateFlagWatchRoot
                        | kFSEventStreamCreateFlagNoDefer
                )
            )
        else {
            throw Failure(path: root.path, step: .create)
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw Failure(path: root.path, step: .start)
        }
        self.stream = stream
        self.handler = handler
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
