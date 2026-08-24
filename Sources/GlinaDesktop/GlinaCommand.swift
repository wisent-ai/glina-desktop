import Foundation

/// The workflows the desktop offers. A pure UI concept: each case carries a
/// title and a symbol, and the model maps the selection to a backend
/// endpoint. No executable invocation is built from this state.
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
}

struct GlinaCommandDraft: Equatable, Sendable {
    var action: GlinaAction = .sculpt
    var prompt = ""
    /// Round cap sent with the sculpt request.
    var rounds = 12
    var assetPath = ""

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
}
