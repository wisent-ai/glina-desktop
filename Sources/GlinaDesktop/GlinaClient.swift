import Foundation

/// The parsed end of one backend exchange: what to show, what failed, and
/// which artifact paths the result named.
struct GlinaOutcome: Sendable {
    /// 0 on success; mirrors the exit code the workflow would have had.
    let status: Int
    /// Pretty-printed JSON document the endpoint returned.
    let document: String
    /// stderr text collected from streamed log events.
    let stderrText: String
    /// The product's own refusal sentence, when the workflow failed.
    let refusal: String?
    /// Artifact paths (outPath/file/path) named by the result document.
    let paths: [String]
}

struct GlinaAssetImport: Decodable, Equatable {
    let status: String
    let source: String?
    let id: String?
    let path: String?
    let reason: String?

    var accepted: Bool {
        status == "imported" || status == "unchanged"
    }
}

/// Glina operations, each one finite `glina` command. A command's output
/// feeds the live log in its own order; its exit status and the JSON document
/// it printed last are the result.
struct GlinaClient: Sendable {

    private static let pathKeys = ["outPath", "file", "path"]

    // MARK: - Reads

    func config() async throws -> GlinaOutcome {
        try await run(["check-config"]) { _ in }
    }

    func welesTools() async throws -> GlinaOutcome {
        try await run(["weles-tools"]) { _ in }
    }

    /// An unhealthy session exits 1 and says so on stdout alone; surface the
    /// probe's own sentence as the refusal instead of an empty one.
    func blenderHealth() async throws -> GlinaOutcome {
        let outcome = try await run(["blender-health"]) { _ in }
        guard outcome.status != 0, outcome.stderrText.isEmpty else { return outcome }
        return GlinaOutcome(
            status: outcome.status,
            document: outcome.document,
            stderrText: outcome.stderrText,
            refusal: "Blender MCP server answered but the execute_blender_code probe failed",
            paths: []
        )
    }

    // MARK: - Workflows

    func sculpt(prompt: String, rounds: Int, onLog: @escaping @MainActor (String) -> Void) async throws -> GlinaOutcome {
        try await run(["sculpt", prompt, "--rounds", String(rounds)], onLog: onLog)
    }

    func verify(path: String, onLog: @escaping @MainActor (String) -> Void) async throws -> GlinaOutcome {
        try await run(["verify", path], onLog: onLog)
    }

    func previewAnim(path: String, clip: String, onLog: @escaping @MainActor (String) -> Void) async throws -> GlinaOutcome {
        try await run(clip.isEmpty ? ["preview-anim", path] : ["preview-anim", path, "--clip", clip], onLog: onLog)
    }

    func importAsset(
        source: String,
        name: String? = nil,
        onLog: @escaping @MainActor (String) -> Void
    ) async throws -> GlinaOutcome {
        var arguments = ["import", source]
        if let name, !name.isEmpty {
            arguments += ["--name", name]
        }
        return try await run(arguments, onLog: onLog)
    }

    // MARK: - Transport

    private func run(
        _ arguments: [String],
        onLog: @escaping @MainActor (String) -> Void
    ) async throws -> GlinaOutcome {
        let result = try await GlinaCommand.run(arguments, onLog: onLog)
        let object = Self.lastDocument(in: result.stdout)
        let refusal: String?
        if result.status == 0 {
            refusal = nil
        } else {
            let lastLine = result.stderr
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { !$0.isEmpty }
            refusal = lastLine ?? "The run failed."
        }
        return GlinaOutcome(
            status: Int(result.status),
            document: object.map { Self.pretty($0) }
                ?? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderrText: result.stderr,
            refusal: refusal,
            paths: object.map(Self.extractPaths) ?? []
        )
    }

    // MARK: - JSON helpers

    /// The JSON document a command printed last: the CLI pretty-prints its
    /// result, so it starts at the last line that opens an object.
    private static func lastDocument(in stdout: String) -> [String: Any]? {
        let lines = stdout.components(separatedBy: "\n")
        for start in lines.indices.reversed() where lines[start].hasPrefix("{") {
            let candidate = lines[start...].joined(separator: "\n")
            if let data = candidate.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    private static func pretty(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    private static func extractPaths(from object: [String: Any]) -> [String] {
        pathKeys.compactMap { object[$0] as? String }
    }
}
