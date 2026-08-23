import Foundation

/// Every Glina command the desktop can run. The UI never grows a second
/// interpretation of the CLI: one draft builds the argv, the command preview
/// and the subprocess invocation.
enum GlinaAction: String, CaseIterable, Identifiable, Sendable {
    case sculpt, verify, config, blenderHealth, welesTools, assets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sculpt: return "Sculpt"
        case .verify: return "Verify"
        case .config: return "Check Config"
        case .blenderHealth: return "Blender Health"
        case .welesTools: return "Weles Tools"
        case .assets: return "Assets"
        }
    }

    var symbol: String {
        switch self {
        case .sculpt: return "hammer"
        case .verify: return "checkmark.seal"
        case .config: return "list.bullet.rectangle"
        case .blenderHealth: return "waveform.path.ecg"
        case .welesTools: return "globe"
        case .assets: return "cube.transparent"
        }
    }

    /// The `glina` subcommand behind this workflow; assets is app-local.
    var subcommand: String? {
        switch self {
        case .sculpt: return "sculpt"
        case .verify: return "verify"
        case .config: return "check-config"
        case .blenderHealth: return "blender-health"
        case .welesTools: return "weles-tools"
        case .assets: return nil
        }
    }
}

struct GlinaCommandDraft: Equatable, Sendable {
    var action: GlinaAction = .sculpt
    var prompt = ""
    /// Round cap forwarded as the CLI's own `--rounds` flag.
    var rounds = 12
    var assetPath = ""

    var arguments: [String] {
        switch action {
        case .sculpt:
            return ["sculpt", prompt, "--rounds", String(rounds)]
        case .verify:
            return ["verify", assetPath]
        case .config:
            return ["check-config"]
        case .blenderHealth:
            return ["blender-health"]
        case .welesTools:
            return ["weles-tools"]
        case .assets:
            return []
        }
    }

    var commandLine: String {
        (["glina"] + arguments.map(Self.quote)).joined(separator: " ")
    }

    var validationProblem: String? {
        switch action {
        case .sculpt:
            return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Describe the asset to sculpt." : nil
        case .verify:
            return assetPath.isEmpty ? "Choose a .glb file." : nil
        case .config, .blenderHealth, .welesTools, .assets:
            return nil
        }
    }

    private static func quote(_ word: String) -> String {
        guard word.contains(where: { $0.isWhitespace || "'\"\\$".contains($0) }) else { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct GlinaCommandResult: Sendable {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

/// Accumulates both streams under a lock while readability handlers drain
/// them; every chunk leaves with a sequence number so the live log keeps the
/// process's exact interleaving.
final class OutputSink: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = ""
    private var standardError = ""
    private var openStreams = 0
    private var sequence = 0
    let deliver: @Sendable (Int, String) -> Void

    init(deliver: @escaping @Sendable (Int, String) -> Void) {
        self.deliver = deliver
    }

    func openStream() {
        lock.lock(); openStreams += 1; lock.unlock()
    }

    func consume(_ data: Data, isError: Bool) {
        lock.lock()
        let text = String(decoding: data, as: UTF8.self)
        if isError { standardError += text } else { standardOutput += text }
        sequence += 1
        let order = sequence
        lock.unlock()
        deliver(order, text)
    }

    func closeStream() {
        lock.lock(); openStreams -= 1; lock.unlock()
    }

    func waitUntilDrained(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock(); let busy = openStreams > 0; lock.unlock()
            if !busy { return }
            usleep(20_000)
        }
    }

    var collected: (standardOutput: String, standardError: String) {
        lock.lock(); defer { lock.unlock() }
        return (standardOutput, standardError)
    }
}

actor GlinaCommandRunner {
    private var resolvedExecutable: URL?

    func run(
        arguments: [String],
        onChunk: @escaping @Sendable (Int, String) -> Void
    ) async throws -> GlinaCommandResult {
        let executable = try executableURL()
        return try await Task.detached(priority: .userInitiated) {
            let sink = OutputSink(deliver: onChunk)
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            sink.openStream()
            sink.openStream()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    sink.closeStream()
                    return
                }
                sink.consume(data, isError: false)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    sink.closeStream()
                    return
                }
                sink.consume(data, isError: true)
            }
            try process.run()
            process.waitUntilExit()
            sink.waitUntilDrained(timeout: 5)
            let collected = sink.collected
            return GlinaCommandResult(
                status: process.terminationStatus,
                standardOutput: collected.standardOutput,
                standardError: collected.standardError
            )
        }.value
    }

    private func executableURL() throws -> URL {
        if let resolvedExecutable { return resolvedExecutable }
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
            throw GlinaCommandError.executableMissing
        }
        resolvedExecutable = found
        return found
    }
}

enum GlinaCommandError: LocalizedError {
    case executableMissing
    var errorDescription: String? {
        "Glina CLI is not installed. Install it with `npm install -g @wisent-ai/glina`, then refresh this window."
    }
}
