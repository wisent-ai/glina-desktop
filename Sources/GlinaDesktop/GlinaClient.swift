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

enum GlinaClientError: LocalizedError {
    case notHTTP
    case streamClosedEarly

    var errorDescription: String? {
        switch self {
        case .notHTTP:
            return "Glina returned an unreadable response."
        case .streamClosedEarly:
            return "The run ended before a result was available."
        }
    }
}

/// HTTP/JSON client for the local Glina backend. Reads are plain GETs;
/// long-running workflows POST and stream NDJSON — each log event feeds the
/// live log in the backend's own order, and the single result event carries
/// the status and the result document.
struct GlinaClient: Sendable {
    let baseURL: URL

    private static let pathKeys = ["outPath", "file", "path"]

    // MARK: - Reads

    func config() async throws -> GlinaOutcome {
        try await get("config")
    }

    func welesTools() async throws -> GlinaOutcome {
        try await get("weles-tools")
    }

    /// A failed probe is still a 200, with {"ok":false,"error":...}; surface
    /// that sentence as the refusal instead of reporting success.
    func blenderHealth() async throws -> GlinaOutcome {
        let outcome = try await get("blender-health")
        guard outcome.status == 0,
              let data = outcome.document.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["ok"] as? Bool) == false
        else { return outcome }
        return GlinaOutcome(
            status: 1,
            document: outcome.document,
            stderrText: "",
            refusal: (object["error"] as? String) ?? "The Blender session did not answer.",
            paths: []
        )
    }

    // MARK: - Workflows

    func sculpt(prompt: String, rounds: Int, onLog: @escaping @MainActor (String) -> Void) async throws -> GlinaOutcome {
        let body: [String: Any] = ["prompt": prompt, "rounds": rounds, "outDir": NSNull()]
        return try await postStreaming("sculpt", body: body, onLog: onLog)
    }

    func verify(path: String, onLog: @escaping @MainActor (String) -> Void) async throws -> GlinaOutcome {
        try await postStreaming("verify", body: ["path": path], onLog: onLog)
    }

    func previewAnim(path: String, clip: String, onLog: @escaping @MainActor (String) -> Void) async throws -> GlinaOutcome {
        try await postStreaming("preview-anim", body: ["path": path, "clip": clip], onLog: onLog)
    }

    // MARK: - Transport

    private func get(_ endpoint: String) async throws -> GlinaOutcome {
        let url = baseURL.appendingPathComponent("v1").appendingPathComponent(endpoint)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw GlinaClientError.notHTTP }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let document = Self.pretty(object, fallback: data)
        guard (200...299).contains(http.statusCode) else {
            return GlinaOutcome(
                status: 1,
                document: document,
                stderrText: "",
                refusal: (object?["error"] as? String)
                    ?? "Glina returned an error.",
                paths: []
            )
        }
        return GlinaOutcome(
            status: 0,
            document: document,
            stderrText: "",
            refusal: nil,
            paths: object.map(Self.extractPaths) ?? []
        )
    }

    private func postStreaming(
        _ endpoint: String,
        body: [String: Any],
        onLog: @escaping @MainActor (String) -> Void
    ) async throws -> GlinaOutcome {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1").appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw GlinaClientError.notHTTP }

        // A non-2xx before the stream starts is the error envelope.
        guard (200...299).contains(http.statusCode) else {
            var data = Data()
            for try await line in bytes.lines {
                data.append(contentsOf: line.utf8)
                data.append(UInt8(ascii: "\n"))
            }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return GlinaOutcome(
                status: 1,
                document: Self.pretty(object, fallback: data),
                stderrText: "",
                refusal: (object?["error"] as? String)
                    ?? "Glina returned an error.",
                paths: []
            )
        }

        var stderrText = ""
        var resultStatus: Int?
        var resultObject: [String: Any]?
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = event["type"] as? String
            else { continue }
            switch type {
            case "log":
                let chunk = event["chunk"] as? String ?? ""
                if event["stream"] as? String == "stderr" { stderrText += chunk }
                await onLog(chunk)
            case "result":
                resultStatus = event["status"] as? Int
                resultObject = event["json"] as? [String: Any]
            default:
                continue
            }
        }
        guard let status = resultStatus else { throw GlinaClientError.streamClosedEarly }

        let refusal: String?
        if status == 0 {
            refusal = nil
        } else {
            let trimmed = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            refusal = trimmed.isEmpty
                ? "The run failed."
                : trimmed
        }
        return GlinaOutcome(
            status: status,
            document: resultObject.map { Self.pretty($0, fallback: nil) } ?? "",
            stderrText: stderrText,
            refusal: refusal,
            paths: resultObject.map(Self.extractPaths) ?? []
        )
    }

    // MARK: - JSON helpers

    private static func pretty(_ object: [String: Any]?, fallback: Data?) -> String {
        if let object,
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let fallback, let text = String(data: fallback, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func extractPaths(from object: [String: Any]) -> [String] {
        pathKeys.compactMap { object[$0] as? String }
    }
}
