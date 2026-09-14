# Native character close-up, 2026-09-08

The isolated native Godot capture exited successfully with
`CHARACTER_NATIVE_CAPTURE_COMPLETE` in `native.log`. It uses the actual selected
actor, model visual, displacement gait, secondary-motion spring, and footfall
module. It does not import assets or modify gameplay. The plain stage provides
visual ground only; this is not an integrated collision or room journey.

Reproduce from the repository root after normal asset import:

```sh
godot --path apps/world --script "$PWD/evidence/world/inhabited-polish/character-native/capture.gd" --audio-driver Dummy --log-file "$PWD/evidence/world/inhabited-polish/character-native/native.log"
```

The capture harness currently uses the workstation's absolute output directory.
The six PNGs and `capture-record.json` record idle, running at 6 m/s, an
orthogonal turn, a wider soil footfall, stopping, and reduced motion.

## Observations

- Upper loose hair bends subtly while running and turning. The helmet stays
  visually rigid in the frontal and profile views; no obvious tearing appears
  at the weighted hair transition. This is a small upper-strand treatment, not
  a whole-head, lower-hair, or cloth simulation.
- The running spring records approximately 0.053 radians of pitch. Turning
  adds approximately 0.018 radians of lateral response. After 20 stopped
  physics ticks the residual angles are approximately 0.0076 and 0.0011
  radians: settling is visible in the state record, rather than an immediate
  discontinuity.
- Four actual gait contacts occur before stopping; the stopped capture retains
  four contacts and has dust emission off. The wider running image shows only
  a few small soil motes, restrained relative to the actor.
- Reduced motion records zero secondary angles, the idle clip, and no dust
  emission while physical displacement continues. Contact accounting continues
  independently of those decorative effects.
- Audio is disabled in every recorded frame. This verifies visual behavior and
  muted configuration; no human audio audition was performed.

## Limits

The plain floor and wider views expose some foot-to-ground/shadow separation.
The operator's existing 0.15 m model floor offset is unchanged by this work;
these captures do not establish that the separation is a new regression or
qualify integrated floor contact. No geometry or gameplay adjustment was made
from this observation. The parent integrated journey must assess the final
room floors and camera scale.

These still frames sample actual running motion, but are not a continuous
video. Exact helmet-pose preservation, bounded spring response, source mesh
identity, and material/clip preservation are additionally covered by the
focused tests and source audit in the parent evidence directory. The isolated
stage has neither final colony lighting nor surrounding furnishings.
