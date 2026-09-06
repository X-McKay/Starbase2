# Aster kit in the playable colony

Status: accepted

Date: 2026-09-05. Scope: local Godot rollout authorized after review of the art
pilot. No deployment, backend migration or new operational authority.

The subsequent [building catalog milestone](building-catalog.md) replaces the
procedural building variants with asset definitions and authored interiors. The
record below describes the earlier rollout and its validation.

## Implemented

The workshop, command building and trial hall now use the approved PNG kit for
their exterior walls, entrances and roof panels. Their engineering pack, sensor
tower and training-ring silhouettes remain distinct. Plaza flooring and habitat
front cladding use the same atlas. Exterior building collision footprints remain
compatible with colony routes; the habitat and greenhouse remain decorative.

All three operational buildings have playable interiors. They reuse the same
floor, bulkhead and console modules, with workshop storage, command seating and
trial apparatus as layout variants. `colony_room.gd` owns each room's prop bounds,
collision and click-navigation grid. Cutaway side/front edges remain physically
bounded; a roof does not obscure indoor movement.

Run `mise exec -- just world`:

- Approach a main entrance and press **F** to enter. Press **F** inside, or use
  **Return to colony**, to leave at the corresponding exterior door.
- Walk with WASD/arrows or click clear floor; furniture and room edges block
  movement. Approach the central console or crew member and press **E** to open
  the existing inspector.
- From anywhere, **1 / 2 / 3** or the crew directory opens the same inspector.
  **Visit this room** enters its interior without requiring a spatial journey.
- **M** returns from an interior to the colony overview. Journal, evidence,
  cancellation and explicit command controls remain independently accessible.

Interiors are separate ten-unit room instances reached by a direct camera cut.
They are intentionally larger than the exterior collision envelope, a common
RPG spatial convention rather than a seamless architectural model. Entering
repositions the existing crew character locally; it creates no duplicate crew
identity and represents no operational event. Exiting restores its outdoor
position. Crew motion is still while indoors; reduced motion is respected.
Exterior terrain and sky are hidden during the interior view and restored on exit.

## Authoritative state

The room label and crew label use the existing `StateView.crew_activity` projection
from the core snapshot. Stale, unknown/offline, no recorded work and retained
outcomes remain distinct. E opens the same selected records, evidence and command
form used outdoors. Painted screen diagrams, lights and trial apparatus are
decorative. Visiting, walking and inspecting dispatch no work and award no XP.
Fixture captures remain labeled and cannot enable operational commands.

## Validation and limits

The missing room transition was reproduced in
[before.log](../evidence/world-rollout/before.log). The room test exercises three
door journeys, mouse routes around furniture, physical prop and cutaway-edge
contact, route recovery, console inspection, direct visits, room switching, map
exit and absence of dispatch. Existing state, navigation, crew, interaction and
native command tests also run through `just check-world`.

Actual native captures and measurements are recorded in
[validation.json](../evidence/world-rollout/validation.json), including the
[colony](../evidence/world-rollout/colony.png),
[workshop](../evidence/world-rollout/workshop.png),
[command room](../evidence/world-rollout/command.png),
[trial hall](../evidence/world-rollout/trial-hall.png) and
[compact stale inspector](../evidence/world-rollout/stale-interior.png).
Short frame samples are capped process-frame intervals, not GPU timings or proof
of a performance improvement. No second-platform or export qualification was run.

The rollout establishes reuse across three playable rooms and their exteriors.
It does not finish all art production: authored door/crew animation, seamless
exterior/interior geometry, dedicated corner assets, lighting masks, sound and
consistent production texel density remain open. Roof behavior is an immediate
cutaway on entering an instanced room, not an animated roof fade. Owner: Al with
implementation assistance; the next art gate is an in-game review of these three
journeys at intended zoom, then refinement of the shared kit before adding rooms.
