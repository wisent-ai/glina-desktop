// The forms of the workflows that mirror the rest of the CLI: create,
// animate, showcase, the declarations the two read, config export and setup.
// Each asks only for what its one `glina` run takes; the run's refusals are
// the CLI's own and are shown by the result panel.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

extension GlinaRootView {

    var createForm: some View {
        WisentSectionBox(
            title: "Prompt", detail: "The studio flow through the Weles browser layer."
        ) {
            VStack(spacing: WisentDesign.Space.x3) {
                TextField("dwarven axe warrior", text: $model.draft.prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
                TextField(
                    "race (optional): humans, dwarves, elves, skeletons", text: $model.draft.race
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    var animateForm: some View {
        WisentSectionBox(
            title: "Animate",
            detail: "A declared preset's visibly moving actions, applied to an asset."
        ) {
            VStack(spacing: WisentDesign.Space.x3) {
                HStack(spacing: WisentDesign.Space.x3) {
                    TextField(
                        "asset .glb (empty: the active imported asset)",
                        text: $model.draft.assetPath
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("Browse…") { chooseGlb(for: "Choose the .glb to animate.") }
                }
                TextField("preset name, as glina presets lists it", text: $model.draft.preset)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    var showcaseForm: some View {
        WisentSectionBox(title: "Showcase", detail: "Build a declared animated reference asset.") {
            TextField(
                "showcase asset name, as glina showcases lists it", text: $model.draft.showcaseAsset
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    var declarationsForm: some View {
        WisentSectionBox(
            title: "Declarations",
            detail:
                "The showcases and presets glina showcase and glina animate read: list them, add one from a JSON file, or remove one."
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Picker("Kind", selection: $model.draft.declarationKind) {
                    ForEach(GlinaDeclarationKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                }
                .pickerStyle(.segmented)
                Picker("Action", selection: $model.draft.declarationVerb) {
                    ForEach(GlinaDeclarationVerb.allCases) { verb in Text(verb.rawValue).tag(verb) }
                }
                .pickerStyle(.segmented)
                if model.draft.declarationVerb != .list {
                    TextField(
                        "name: lowercase letters, digits and dashes",
                        text: $model.draft.declarationName
                    )
                    .textFieldStyle(.roundedBorder)
                }
                if model.draft.declarationVerb == .add {
                    HStack(spacing: WisentDesign.Space.x3) {
                        TextField("declaration .json", text: $model.draft.declarationFile)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { chooseDeclarationFile() }
                    }
                }
                if model.draft.declarationVerb == .remove {
                    Text(
                        "Removing a declaration deletes its file; glina animate and glina showcase then refuse the name and list what remains."
                    )
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.muted)
                }
            }
        }
    }

    var workspaceForm: some View {
        WisentSectionBox(
            title: "Workspace",
            detail:
                "The assets imported into Glina's workspace: list them, make one the active input, or take one out and delete the workspace's copy; the file it came from stays."
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Picker("Action", selection: $model.draft.workspaceVerb) {
                    ForEach(GlinaWorkspaceVerb.allCases) { verb in Text(verb.rawValue).tag(verb) }
                }
                .pickerStyle(.segmented)
                if model.draft.workspaceVerb != .list {
                    TextField("asset id, as the list shows it", text: $model.draft.workspaceAsset)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    var exportConfigForm: some View {
        WisentSectionBox(
            title: "Export config",
            detail:
                "A resolved, owner-only copy of the config for a remote run; every skarbiec:// reference is answered here and the file is written with mode 0600."
        ) {
            HStack(spacing: WisentDesign.Space.x3) {
                TextField("/path/to/resolved-config.json", text: $model.draft.exportPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseExportPath() }
            }
        }
    }

    var setupForm: some View {
        WisentSectionBox(
            title: "Setup",
            detail: "Provision Blender, uv and the Blender MCP bridge, or only locate them."
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                Toggle(
                    "Only check what is installed; install nothing",
                    isOn: $model.draft.setupCheckOnly)
                Toggle("Dry run: say what provisioning would do", isOn: $model.draft.setupDryRun)
            }
        }
    }

    func chooseGlb(for message: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "glb") ?? .data]
        panel.message = message
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.assetPath = url.path
        }
    }

    private func chooseDeclarationFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = "Choose the JSON file that declares the showcase or preset."
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.declarationFile = url.path
        }
    }

    private func chooseExportPath() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "glina-config.resolved.json"
        panel.message = "Where the resolved config is written."
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.exportPath = url.path
        }
    }
}
