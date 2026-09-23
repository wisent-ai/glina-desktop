import Foundation

/// One Glina CLI run per operation.
///
/// The app used to start `glina serve --port 0` on first use and keep it for
/// as long as it ran: a second resident Glina process with its own loopback
/// port. Every operation is now one finite `glina` command. Its output is
/// forwarded as it arrives, and the run ends with the command's exit status
/// and everything it printed, so the window shows the same document and the
/// same refusal an operator sees in a terminal.
enum GlinaCommand {
    struct Outcome: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// The installed `glina` executable: the PATH entries first, then the
    /// well-known install locations.
    static func executable() throws -> URL {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("glina") }
            + [
                home.appendingPathComponent(".stado/bin/glina"),
                home.appendingPathComponent(".local/bin/glina"),
                URL(fileURLWithPath: "/opt/homebrew/bin/glina"),
                URL(fileURLWithPath: "/usr/local/bin/glina"),
            ]
        guard let found = candidates.first(where: { manager.isExecutableFile(atPath: $0.path) }) else {
            throw GlinaBackendError.executableMissing
        }
        return found
    }

    /// Run `glina arguments` to completion, handing each chunk it writes to
    /// `onLog` in arrival order.
    static func run(
        _ arguments: [String],
        onLog: @escaping @MainActor (String) -> Void
    ) async throws -> Outcome {
        let executable = try executable()
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        let run = RunState()
        return try await withCheckedThrowingContinuation { continuation in
            run.attach(continuation)
            for (pipe, stream) in [(stdout, RunState.Stream.stdout), (stderr, .stderr)] {
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        handle.readabilityHandler = nil
                        run.closed(stream)
                        return
                    }
                    let text = String(decoding: data, as: UTF8.self)
                    run.append(text, to: stream)
                    Task { @MainActor in onLog(text) }
                }
            }
            process.terminationHandler = { finished in
                run.exited(finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                run.fail(GlinaBackendError.failedToStart(error.localizedDescription))
            }
        }
    }
}

/// Lock-guarded state of one run: the output of both streams, which of them
/// has closed, the exit status, and the once-only resume of the caller.
private final class RunState: @unchecked Sendable {
    enum Stream { case stdout, stderr }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<GlinaCommand.Outcome, Error>?
    private var stdout = ""
    private var stderr = ""
    private var open: Set<Stream> = [.stdout, .stderr]
    private var status: Int32?

    func attach(_ continuation: CheckedContinuation<GlinaCommand.Outcome, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func append(_ text: String, to stream: Stream) {
        lock.withLock {
            switch stream {
            case .stdout: stdout += text
            case .stderr: stderr += text
            }
        }
    }

    func closed(_ stream: Stream) {
        finishIfDone { open.remove(stream) }
    }

    func exited(_ code: Int32) {
        finishIfDone { status = code }
    }

    func fail(_ error: Error) {
        let waiting = lock.withLock { () -> CheckedContinuation<GlinaCommand.Outcome, Error>? in
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(throwing: error)
    }

    /// The run is over once the process exited and both pipes reached end of
    /// file, so no output written just before exit is lost.
    private func finishIfDone(_ change: () -> Void) {
        let ready = lock.withLock { () -> (CheckedContinuation<GlinaCommand.Outcome, Error>, GlinaCommand.Outcome)? in
            change()
            guard open.isEmpty, let status, let waiting = continuation else { return nil }
            continuation = nil
            return (waiting, GlinaCommand.Outcome(status: status, stdout: stdout, stderr: stderr))
        }
        if let ready {
            ready.0.resume(returning: ready.1)
        }
    }
}

enum GlinaBackendError: LocalizedError {
    case executableMissing
    case failedToStart(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "Glina is not installed."
        case .failedToStart(let reason):
            return "Glina could not start. \(reason)"
        }
    }
}
