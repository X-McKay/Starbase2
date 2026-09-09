# Authored ventilation fan

[Native Compatibility capture](native.png) was visually inspected: recessed
blades, protective bars, rim, fasteners and the wall housing are legible. This is
an isolated asset view; it does not certify room composition or owner approval.

[Native log](native.log) records Godot 4.7.2 / Apple M5 OpenGL 4.1 and the passing
focused test: centered imported rotor, visible rotation, frozen phase for reduced
motion and hidden rooms, resumed phase on visibility, and no collision bodies.

[Background build](build.log) passed using Blender 5.2.1. The initial sandboxed
Blender process crashed; its [log](build-sandbox-failed.log) is retained. The
[import log](import.log) includes host certificate/editor-settings permission
messages; native execution subsequently passed without runtime errors.

```sh
mise exec -- godot --path apps/world --rendering-method gl_compatibility --script res://test_colony_vent.gd
```

The focused test can run headless for behavior assertions; the native invocation
also writes the capture above. Full-world placement and export remain part of
the parent inhabited-polish acceptance run.

The initial attachment filter used operational interaction kinds, which are empty
for Habitat and Botanical scenery. It was corrected to use structure definition
IDs. The extended test instantiates the actual five-station colony and checks
attachment to all four requested interiors, idempotence, and Engineering
exclusion. [Native attachment checks](attachment-native.log) passed cleanly;
[headless checks](attachment.log) also passed assertions with host logger and
certificate messages. No world hookup is needed by this isolated test.
