import Foundation

/// The workflows the desktop offers. A pure UI concept: each case carries a
/// title and a symbol, and the model maps the selection to a backend
/// endpoint. No executable invocation is built from this state.
enum GlinaAction: String, CaseIterable, Identifiable, Sendable {
    case sculpt, create, verify, animate, showcase, declarations, workspace, config, exportConfig,
        doctor, setup, assets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sculpt: return "Sculpt"
        case .create: return "Create"
        case .verify: return "Verify"
        case .animate: return "Animate"
        case .showcase: return "Showcase"
        case .declarations: return "Declarations"
        case .workspace: return "Workspace"
        case .config: return "Check Config"
        case .exportConfig: return "Export Config"
        case .doctor: return "Doctor"
        case .setup: return "Setup"
        case .assets: return "Assets"
        }
    }

    var symbol: String {
        switch self {
        case .sculpt: return "hammer"
        case .create: return "wand.and.stars"
        case .verify: return "checkmark.seal"
        case .animate: return "figure.walk.motion"
        case .showcase: return "sparkles.tv"
        case .declarations: return "list.bullet.clipboard"
        case .workspace: return "tray.full"
        case .config: return "list.bullet.rectangle"
        case .exportConfig: return "square.and.arrow.up"
        case .doctor: return "waveform.path.ecg"
        case .setup: return "shippingbox"
        case .assets: return "cube.transparent"
        }
    }
}

struct GlinaCommandDraft: Equatable, Sendable {
    var action: GlinaAction = .sculpt
    var prompt = ""
    /// Round cap for this sculpt, as the operator typed it. Empty sends none,
    /// and Glina takes `llm.maxRounds` from its config or refuses by name.
    var rounds = ""
    var assetPath = ""
    /// `create`: the race the studio flow draws the asset for; empty sends none.
    var race = ""
    /// `animate`: the declared preset to apply.
    var preset = ""
    /// `showcase`: the declared showcase asset to build.
    var showcaseAsset = ""
    /// `declarations`: which kind, which verb, and the name and file a verb takes.
    var declarationKind: GlinaDeclarationKind = .presets
    var declarationVerb: GlinaDeclarationVerb = .list
    var declarationName = ""
    var declarationFile = ""
    /// `workspace`: list the imported assets, make one active, or take one out.
    var workspaceVerb: GlinaWorkspaceVerb = .list
    var workspaceAsset = ""
    /// `config export`: where the resolved, owner-only config is written.
    var exportPath = ""
    /// `setup`: only locate the tooling, or only say what provisioning would do.
    var setupCheckOnly = true
    var setupDryRun = false

    var validationProblem: String? {
        switch action {
        case .sculpt, .create:
            if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Describe the asset to make."
            }
            if action == .sculpt, !rounds.isEmpty, roundCap == nil {
                return
                    "Max rounds must be a whole number above zero, or empty to use the config's llm.maxRounds."
            }
            return nil
        case .verify:
            return assetPath.isEmpty ? "Choose a .glb file." : nil
        case .animate:
            return preset.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Name the declared preset to apply." : nil
        case .showcase:
            return showcaseAsset.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Name the declared showcase asset." : nil
        case .declarations:
            switch declarationVerb {
            case .list: return nil
            case .add:
                if declarationName.trimmingCharacters(in: .whitespaces).isEmpty {
                    return "Name the declaration."
                }
                return declarationFile.isEmpty ? "Choose the JSON file that declares it." : nil
            case .remove:
                return declarationName.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Name the declaration to remove." : nil
            }
        case .workspace:
            if workspaceVerb == .list { return nil }
            return workspaceAsset.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Name the imported asset, as the list shows its id." : nil
        case .exportConfig:
            return exportPath.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Say where the resolved config should be written." : nil
        case .config, .doctor, .setup, .assets:
            return nil
        }
    }

    /// The typed round cap, when it is a whole number above zero.
    var roundCap: Int? {
        guard let value = Int(rounds.trimmingCharacters(in: .whitespaces)), value > 0 else {
            return nil
        }
        return value
    }
}

/// The two declaration kinds `glina showcases` and `glina presets` manage.
enum GlinaDeclarationKind: String, CaseIterable, Identifiable, Sendable {
    case showcases, presets

    var id: String { rawValue }
}

/// What a declaration run does: the verbs the CLI takes after the kind.
enum GlinaDeclarationVerb: String, CaseIterable, Identifiable, Sendable {
    case list, add, remove

    var id: String { rawValue }
}

/// What a workspace run does: the verbs `glina workspace` takes.
enum GlinaWorkspaceVerb: String, CaseIterable, Identifiable, Sendable {
    case list, select, remove

    var id: String { rawValue }
}
