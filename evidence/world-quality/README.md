# World quality evidence

Date: 2026-09-07. Local visual and functional checks for the
[world quality pass](../../docs/world-quality.md); not a performance benchmark
and not an agent-quality comparison.

- `before-*.png`: the prior walking view, colony overview and three interiors,
  rendered on the same virtual display from the same labelled synthetic
  [fixture](../../fixtures/world/stale.json).
- `normal.png`, `overview.png`, `repair.png`, `review.png`, `gym.png`,
  `landing.png`, `repair-reduced-motion.png`: the same views after the pass, plus
  the landing apron with the cargo yard and rover, and an interior under reduced
  motion (dust stopped).
- `check-world.log`: the complete `just check-world` suite after the change.
- `*.png.json`: capture metadata written by the client, including draw calls.
  Frame intervals come from Mesa software rendering on a shared container and
  are not a performance measurement.

Capture recipe (repository root; absolute fixture path):

```sh
xvfb-run -a -s "-screen 0 1280x800x24" godot --path apps/world --max-fps 60 -- \
  --fixture="$PWD/fixtures/world/stale.json" \
  --capture="$PWD/evidence/world-quality/repair.png" --frames=90 --room=repair
```
