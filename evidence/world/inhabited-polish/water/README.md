# Water material comparison

The inhabited-polish material pass adds crossing ocean swells, shallow color and
fragmented foam around the existing sea-stack footprints. The mineral spring has
a darker center, a mineral-colored shallow shelf, shore lapping and two subtle
upwelling ripple sources. Both shaders retain the existing owner-controlled
`water_time`; no vertex displacement, geometry, navigation or collision changes
are part of this pass. The extra work is fixed shader arithmetic, with the
existing four-stack loop. No performance improvement is claimed.

## Native evidence

[Baseline log](baseline.log) and [candidate log](candidate.log) record successful
Compatibility rendering on Apple M5 / OpenGL 4.1 / Godot 4.7.2. The native test
renders phases 0 and 5, asserts that they differ, and asserts that two consecutive
frames at the frozen phase are byte-identical. The candidate log has no shader
errors. Captures were visually inspected:

- Spring: [baseline](baseline/spring-phase0.png),
  [candidate](candidate/spring-phase0.png),
  [later phase](candidate/spring-phase5.png).
- Ocean: [baseline](baseline/ocean-phase0.png),
  [candidate](candidate/ocean-phase0.png),
  [later phase](candidate/ocean-phase5.png).

The spring capture uses the actual basin node. The ocean capture deliberately
isolates the actual shader on a plane with four synthetic stack footprints; its
visible rings have no rock meshes in this test. These images prove material
rendering and frozen phases, not the full colony composition or physical journey.
Foam remains stylized rather than a simulated shoreline. The initial sandboxed
native launch aborted; the permitted native launch produced the retained baseline.

[Environment checks](environment.log) passed animation, freeze, resume, room
visibility and spring artwork footprint assertions. That standalone headless run
also logged host logger/certificate and offline polling errors, so it does not
establish clean full-world runtime qualification. The integrated inhabited-polish
journey owns physical boundary and settings checks.

## Reproduce

From the repository root, with a native display:

```sh
mise exec -- godot --path apps/world --rendering-method gl_compatibility --script res://test_water_presentation.gd -- --water-output=/tmp/starbase2-water-review
mise exec -- godot --headless --path apps/world --script res://test_environment.gd
```

The first command requires native rendering and should not be added to a
headless-only test loop. Re-running it captures the current shaders; the retained
baseline images document the pre-edit material, not a separate supported variant.
