# Shift Change physical behavior · 2026-09-10

Status: fixture physical behavior passed; native social appearance is **not yet qualified**.
Owner: implementation assistant. These runs use isolated world fixtures, not production
provider calls. They do not measure rendering performance or establish live acceptance.

## Passed behavior

- Seven authored Habitat/Commons anchors support 70 directed navigation routes:
  five workstations to every anchor and back, including each final authored segment.
- Five actual CharacterBody3D actors traversed home → workstation → home. Outbound
  travel measured 51–87 m; all final home arrivals stopped with empty routes and zero
  commanded motion, 0.102–0.114 m from the destination. Earlier arrivals can resume
  cosmetic wandering; the test records each first stopped arrival independently.
- Shared reservations keep home destinations distinct. Stable identity seeds and
  staggered dwell intervals vary ambient activity without creating backend work.
- Assignments interrupt ambient life. Completion publishes retained evidence and
  redirects home immediately; pausing future duties does not cancel active work.
- Offline/stale and reduced-motion intents hold position and clear work gestures.
  Cross-building cutaway visibility is independent of workstation identity. Failed
  or collision-stalled routes stop and expose a local blocked cue, without retrying
  indefinitely or changing domain state.

See [directed routes](routes-passed.log), [actual physics](physical-passed.log), and
[intent checks](intent-passed.log). The focused `test_crew_home.gd` also passed
reservation, deterministic dwell, seated departure, early completion, visibility
and bounded route-failure cases; its initial terminal output was not retained here.

## Preserved failures and corrections

1. [Old spawn positions](failed-old-spawn.log) left three actors already at their
   workstations, so the first changed-world test correctly failed its real-travel
   requirement. Parent startup now places actors at reserved authored home roots
   before the first physics frame; runtime holds never teleport actors.
2. [Seat routes](failed-seat-routes.log) and [actual returns](failed-seat-return.log)
   failed at GardenWest/GardenEast. Navigation's 0.4 m obstacle padding and 0.5 m grid
   rounded destinations into blocked cells even though physical seat-front clearance
   was 0.35 m. Moving each seat and root together to compatible quarter-metre Z
   positions preserved seat contact and collision clearance. No navigation margin
   or arrival criterion was weakened. Both route and physics checks then passed.
3. Social clip selection passed an earlier headless check, but native
   [standing](../animation/native-before/standing.png) and
   [seated](../animation/native-before/seated.png) captures reveal severe malformed
   deformation/ground placement. The animation owner diagnosed stale parent matrices accumulating child transforms
   in the bake; its replacement still needs native proof. Imported child transforms,
   scale, skeleton-space tracks and contact need qualification together. Clip names and Blender-local
   contact numbers cannot certify native social animation. These failures remain;
   the animation owner must supply corrected native pose/contact evidence.

## Reproduction

From the repository root, with Godot assets imported:

```sh
mise exec -- godot --headless --path apps/world --script test_crew_presentation.gd
mise exec -- godot --headless --path apps/world --script test_crew_home.gd
mise exec -- godot --headless --fixed-fps 60 --path apps/world --script test_crew_home_routes.gd
mise exec -- godot --headless --fixed-fps 60 --path apps/world --script test_live_crew.gd
```

Fixed simulation stepping is not an FPS benchmark. Native poses, readable views,
keyboard journeys, and the current exported artifact require separate acceptance.
