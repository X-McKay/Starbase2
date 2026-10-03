# Observe camera native review · 2026-10-03

Status: local source-checkout visual evidence, not packaged-build qualification or
owner art acceptance. Godot 4.7.2 Compatibility rendered at 1440×900 on Apple M5.
The isolated fixture uses retained offline data and dispatches no command.

- `observe-handoff.png`: both full-body crew and their shared transfer token in
  the Commons from the final side angle, with feet and hands visible.
- `observe-work.png`: seated Command work through the ray-tested over-shoulder
  composition.
- `observe-handoff-initial-occluded.png`: first attempt, with the camera behind
  render-only canopy slats. The sightline ray selected this angle because a
  taller invisible Terrace navigation proxy rejected the visibly clear angle.
- `observe-handoff-missing-crew.png`: corrected camera angle with one fixture
  actor still hidden; the capture fixture now explicitly shows both crew.
- `observe-handoff-foreground-rail.png`: both actors visible but the first
  selected camera angle let the bench rail obscure their legs and lower action.
  Five side angles were rendered and inspected to select the final composition.

The correction excludes invisible Terrace route-grid bodies from the camera's
bounded sightline test, keeps actual colliders in the test, and prefers the
authored angle when candidates are equally clear. The pair angle also avoids
foreground benches and planters. The focused camera check
asserts a blocked angle is replaced, the final Commons angle frames the pair,
movement eases into and out of the exchange, and no work is dispatched. The
rendered frames were inspected after capture. Meshes without collision remain
outside the physics sightline query, so native visual review is still required
for new set dressing or camera angles.
