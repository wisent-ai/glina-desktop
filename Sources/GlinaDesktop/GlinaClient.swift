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
    let variantOf: String?

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

    /// `glina doctor` exits 1 when any check failed and says which on stdout,
    /// in the report itself; the bridges' own stderr chatter is not the
    /// refusal. The refusal is the failed checks, each with the step that broke.
    func doctor() async throws -> GlinaOutcome {
        let outcome = try await run(["doctor"]) { _ in }
        guard outcome.status != 0 else { return outcome }
        let failed = Self.failedChecks(in: outcome.document)
        return GlinaOutcome(
            status: outcome.status,
            document: outcome.document,
            stderrText: outcome.stderrText,
            refusal: failed.isEmpty ? outcome.refusal : failed.joined(separator: "; "),
            paths: []
        )
    }

    // MARK: - Workflows

    func sculpt(prompt: String, rounds: Int?, onLog: @escaping @MainActor (String) -> Void)
        async throws -> GlinaOutcome
    {
        let cap = rounds.map { ["--rounds", String($0)] } ?? []
        return try await run(["sculpt", prompt] + cap, onLog: onLog)
    }

    func verify(path: String, onLog: @escaping @MainActor (String) -> Void) async throws
        -> GlinaOutcome
    {
        try await run(["verify", path], onLog: onLog)
    }

    func previewAnim(path: String, clip: String, onLog: @escaping @MainActor (String) -> Void)
        async throws -> GlinaOutcome
    {
        try await run(
            clip.isEmpty ? ["preview-anim", path] : ["preview-anim", path, "--clip", clip],
            onLog: onLog)
    }

    func previewScene(path: String, onLog: @escaping @MainActor (String) -> Void) async throws
        -> GlinaOutcome
    {
        try await run(["preview-scene", path], onLog: onLog)
    }

    func importAsset(
        source: String,
        name: String? = nil,
        variantOf: String? = nil,
        onLog: @escaping @MainActor (String) -> Void
    ) async throws -> GlinaOutcome {
        var arguments = ["import", source]
        if let name, !name.isEmpty {
            arguments += ["--name", name]
        }
        if let variantOf, !variantOf.isEmpty {
            arguments += ["--variant-of", variantOf]
        }
        return try await run(arguments, onLog: onLog)
    }

    /// `glina create`: the studio flow through the Weles browser layer.
    func create(prompt: String, race: String, onLog: @escaping @MainActor (String) -> Void)
        async throws -> GlinaOutcome
    {
        var arguments = ["create", prompt]
        if !race.isEmpty { arguments += ["--race", race] }
        return try await run(arguments, onLog: onLog)
    }

    /// `glina animate`: the declared preset over the chosen asset, or the active one when the path is empty.
    func animate(path: String, preset: String, onLog: @escaping @MainActor (String) -> Void)
        async throws -> GlinaOutcome
    {
        var arguments = ["animate"]
        if !path.isEmpty { arguments.append(path) }
        arguments += ["--preset", preset]
        return try await run(arguments, onLog: onLog)
    }

    /// `glina showcase`: build the declared animated reference asset.
    func showcase(asset: String, onLog: @escaping @MainActor (String) -> Void) async throws
        -> GlinaOutcome
    {
        try await run(["showcase", asset], onLog: onLog)
    }

    /// `glina showcases|presets list|add|remove`: the declarations the two workflows read.
    func declarations(
        kind: GlinaDeclarationKind, verb: GlinaDeclarationVerb, name: String, file: String
    ) async throws -> GlinaOutcome {
        var arguments = [kind.rawValue, verb.rawValue]
        switch verb {
        case .list: break
        case .add: arguments += [name, file]
        case .remove: arguments.append(name)
        }
        return try await run(arguments) { _ in }
    }

    /// `glina workspace list|select <id>|remove <id>`: the imported assets,
    /// the active one, and the two counterparts of an import.
    func workspace(verb: GlinaWorkspaceVerb, asset: String) async throws -> GlinaOutcome {
        try await run(
            verb == .list ? ["workspace", verb.rawValue] : ["workspace", verb.rawValue, asset]
        ) { _ in }
    }

    /// `glina export-config --out`: the resolved, owner-only config for a remote run.
    func exportConfig(out: String) async throws -> GlinaOutcome {
        try await run(["export-config", "--out", out]) { _ in }
    }

    /// `glina setup`: provision the Blender tooling, or only check or describe it.
    func setup(checkOnly: Bool, dryRun: Bool, onLog: @escaping @MainActor (String) -> Void)
        async throws -> GlinaOutcome
    {
        var arguments = ["setup"]
        if checkOnly { arguments.append("--check") }
        if dryRun { arguments.append("--dry-run") }
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
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                return object
            }
        }
        return nil
    }

    private static func pretty(_ object: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    private static func extractPaths(from object: [String: Any]) -> [String] {
        let artifacts = pathKeys.compactMap { object[$0] as? String }
        if let output = object["outputPath"] as? String { return artifacts + [output] }
        return artifacts
    }

    /// "<name>: <error>" for every check the doctor reported as not ok.
    private static func failedChecks(in document: String) -> [String] {
        guard let data = document.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let checks = object["checks"] as? [[String: Any]]
        else { return [] }
        return checks.compactMap { check in
            guard check["ok"] as? Bool == false, let name = check["name"] as? String else {
                return nil
            }
            let error = check["error"] as? String
            return error.map { "\(name): \($0)" } ?? name
        }
    }
}
