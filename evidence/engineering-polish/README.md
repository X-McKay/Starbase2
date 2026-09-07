# Engineering slice evidence

This is a local game-art review, using offline fixtures; no live operational work
was dispatched by the visual captures. Branch: `feature/meshy-blender`.

- `exterior.png`: closed generated hull, integrated sliding airlock and exterior.
- `interior.png`: continuous authored room, reactor and engineer console gesture.
- `reduced.png`: reduced-motion interior; default-muted sound is tested separately.
- `animation-review.gif`: 48 native Godot frames of idle, walk, run and console.
- `helmet-audit.json`: 25 samples per clip; maximum rigid-region deformation below
  0.001 mm across 1,741 repaired helmet vertices.
- `check-world-accepted.log`: final full world suite and native command fixture.
- `focused-final.log`: focused materials, visibility, route and animation checks.
- `model-preparation.json`: fitted geometry bounds and opened hull doorway.
- `character-preparation.json`: rig, imported clips, model height and repair count.

The final suite passed continuous routes through all five rooms, furniture/edge
collisions, keyboard inspection, offline/stale states, default-muted ambience,
reduced motion, actual-displacement animation and no implicit dispatch. The
native command fixture verified six explicit POSTs and GET-only reconciliation.

Earlier failed checks and visual iterations are retained. They identified rig
control geometry mixed with the skin, bone-tail lengths affecting IK, a console
bake hierarchy issue, an unmapped crew visibility lookup and a check that sampled
visibility before its physics update. Their fixes are covered by the accepted
suite and final native captures. The first package capture was preempted before
writing its interior image; the qualification harness now uses its existing
wall-clock timeout while the scene exits after capture.

See [the art review](../../assets-production/batches/engineering-polish/REVIEW.md) for scope, rebuild,
limitations and the budget ledger: 140 credits this pass, 200 including the
previous 60-credit generation, under the total 250-credit authorization.

## Qualified package

`mise exec -- just check-world-export --output .local/engineering-polish-qualified`
passed. The unsigned local macOS archive, immutable source/pack/executable hashes,
smoke checks, native colony and 960 × 720 reduced-motion interior captures are in
that directory. The first package attempt remains in
`.local/engineering-polish-review` for comparison. This is not a deployed release.
The qualified executable is opened at Engineering with an offline stale fixture
from `.local/engineering-polish-playable` for owner review.
