# Glina Desktop

**Your AI sculpts your game assets.** Native macOS workspace for Glina
text-to-GLB sculpting. It drives the installed `glina` CLI rather than
reimplementing the Brama routing, Blender MCP execution, or the GLB quality
gate.

## Workflows

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

Every screen shows the exact `glina` command it runs. Standard output and the
CLI's own refusal are shown verbatim; the app never paraphrases a gate failure
and never grows a second interpretation of the pipeline.

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
