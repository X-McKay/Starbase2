# Character pipeline experiment · 2026-09-06

Outcome: shared runtime and asset checks implemented; **rigged visual direction
rejected by the user**. Approved illustrated crew remain the game default. See
[the production contract](../../docs/character-production.md) for the remaining
illustrated-animation gate. No new polished 2D walk artwork is claimed.

## Verification

- `check-final.log`: both 36-frame assets, usable RGBA, bounds, unique poses,
  provenance, default illustrated art, displacement gait and real collision tests;
  native lab instantiation and default mute.
- `world-check.log`: affected Godot scene/integration suite.
- `commands-check.log`: native command reconciliation checks.
- `repository-check.log`: formatting, lint/type checks, 34 Rust tests, 45 Python
  tests, generated contracts and documentation validation passed.
- `approved-colony.png`: normal startup with original illustrated characters.
- `showroom-grounded-90.png`: intermediate rigged prototype with approved stills
  for comparison; prompted rejection of this style. It is not a production image.

## Retained failures

`render.log` records the sandboxed Blender crash; native execution succeeded.
`render-native.log` produced clipped forward steps. A shared camera/anchor change
created room beneath the feet (`render-v2.log`). `contracts.log` rejected repeated
poses: Blender's action evaluation restored frame 1 during export. Explicit pose
sampling fixed the first test, then source authoring and export were separated:
all pose matrices are captured before Action keys are added, and the renderer
samples that saved Action. `contracts-final.log` and `check-final.log` pass.

`motion.log` and `motion-diagnostic-v2.log` show that sub-millimeter wall recovery
advanced the gait. A one-millimeter per-tick deadband now leaves it unchanged.
`motion-v3.log` passes real wall, direction, reduced-motion and teleport checks.

`showroom.log` records a GDScript `size()` typo; `showroom-v2.log` exposed the wrong
sign on the sprite's vertical pivot. `showroom-90.png` retains that failed render;
`showroom-grounded-90.png` verifies the corrected anchor. Headless success did not
establish visual correctness.

`source-build-color.log` / `render-color.log` record the last material-color
refinement before the user steered back to the illustrated style. The prototype
sources and generated assets are retained for reproducibility, not selected for
rollout. `pack-source-agnostic.log` repackages them through the editor-neutral
contract. Logs may contain local paths but contain no credentials/provider data.

## Limits

Two distinct atlases only; no 50-character load qualification. Timing in
`showroom-grounded.json` is capture-process timing, not a benchmark. No Windows,
Linux renderer or web-export qualification. No final illustrated walk cycle,
Rigify rig, cloth simulation or production art-quality improvement established.
No movie of the rejected style is presented as an approved result.
