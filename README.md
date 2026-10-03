# Glina Desktop

**Your AI sculpts your game assets.** Native macOS workspace for Glina
text-to-GLB sculpting. It runs the installed `glina` CLI once per operation and
keeps no Glina process between them, rather than reimplementing Brama routing,
Blender MCP execution, GLB verification, or workspace persistence.

## Workflows


- Import an existing `.glb` during first use, from Assets, or from Check Config.
  Assets and Check Config also accept a base asset id to import a distinct
  variant. Glina stages and verifies the exact bytes, persists only accepted
  content, and reports the structured refusal reason when it rejects an import.
  The accepted destination becomes the Assets directory, animation selection,
  and Verify input. A base cannot be removed while variants depend on it.
- Sculpt a game asset from a text prompt, round by round through a live
  Blender MCP session.
- Verify a `.glb` against the structural quality gate (valid glTF container,
  triangle budget, materials/skins/animation presence, file-size bounds).
- Inspect the resolved pipeline configuration — credentials stay redacted by
  the CLI itself; secrets only ever resolve from Skarbiec references.
- Probe the live Blender MCP session health.
- List the browser-layer tools the Weles MCP server exposes.
- Browse output `.glb` and `.png` artifacts with Quick Look and Reveal in Finder.
- Render a selected GLB on neutral ground from Assets with **Preview in scene**.
  The PNG appears in the gallery; a failed Blender import or render appears as
  a refusal rather than a fabricated image.

The app shows the CLI's output and refusals rather than paraphrasing the
quality gate. Each operation runs one finite `glina` command (`check-config`,
`doctor`, `setup`, `export-config`, `sculpt`, `create`, `verify`, `animate`,
`showcase`, `showcases`/`presets`, `preview-anim`, `preview-scene`, `import`,
`workspace`). Output streams into the live log; the exit status and final JSON
document are the result. A rejected import displays its `reason`, while other
failures show stderr or failed doctor checks. Both windows use the same
workspace import as the CLI.

## Requirements

- Apple-silicon macOS 14 or newer.
- Glina installed on PATH, `~/.stado/bin/glina`, or `~/.local/bin/glina`.

Install Glina itself through npm:

```sh
npm install -g @wisent-ai/glina
```

Then build and install the app:

```sh
./release/bundle/build-app.sh
```

The application bundle is installed to `~/Applications/Glina.app` and must be
signed with a stable Developer ID or Apple Development identity.

Releases go through Stado: `.wisent-release.json` runs
`release/stado-release.sh` on a darwin builder, which builds the same bundle
with `GLINA_INSTALL_AFTER_BUILD=no`, signs it with the Developer ID identity
the manifest hands in as `MACOS_SIGN_IDENTITY`, and stages `Glina.app`.
`stado product install glina --surface desktop` installs that release.

## License

MIT
