# Glina Desktop

**Your AI sculpts your game assets.** Native macOS workspace for Glina
text-to-GLB sculpting. It starts the installed `glina serve` loopback backend
and calls product-owned API operations rather than reimplementing Brama routing,
Blender MCP execution, GLB verification, or workspace persistence.

## Workflows


- Import an existing `.glb` during first use, from Assets, or from Check Config.
  Glina stages and verifies the exact bytes, persists only an accepted asset,
  preserves name conflicts, and reports imported, unchanged, conflicting, or
  rejected. The accepted destination becomes the Assets directory, animation
  selection, and Verify input.
- Sculpt a game asset from a text prompt, round by round through a live
  Blender MCP session.
- Verify a `.glb` against the structural quality gate (valid glTF container,
  triangle budget, materials/skins/animation presence, file-size bounds).
- Inspect the resolved pipeline configuration — credentials stay redacted by
  the CLI itself; secrets only ever resolve from Skarbiec references.
- Probe the live Blender MCP session health.
- List the browser-layer tools the Weles MCP server exposes.
- Browse an output directory for produced `.glb` and `.png` artifacts with
  Quick Look preview and Reveal in Finder.

The app shows backend output and refusals rather than paraphrasing the quality
gate. Long operations stream through `glina serve`; import uses the same
`pipeline/workspace.js` operation as the CLI.

## Requirements

- Apple-silicon macOS 14 or newer.
- Glina installed on PATH, `~/.stado/bin/glina`, or `~/.local/bin/glina`.

Install Glina itself through npm:

```sh
npm install -g @wisent-ai/glina
```

Then build and install the app:

```sh
./Scripts/build-app.sh
```

The application bundle is installed to `~/Applications/Glina.app` and must be
signed with a stable Developer ID or Apple Development identity.

## License

MIT
