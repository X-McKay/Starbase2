# Meshy and Blender world pass (historical record)

This document records the earlier shared-rig production slice. It is retained
for provenance and measured lessons; it is not the current character or runtime
source. See [the September refactor](recent-refactor.md) and
[character production](character-production.md) for the active pipeline.

Status: proposed

The continuous colony pass is implemented on `feature/meshy-blender` and remains
subject to owner art review. It expands the Engineering milestone across all five
placed buildings without additional Meshy generation charges.

## Delivered scope

The owner supplied the [reactor laboratory](https://www.meshy.ai/s/it48xz) and
[Cybercat Sentinel](https://www.meshy.ai/s/84fVov) references and approved moving
from sprites to native models. Blender now authors distinct Engineering,
Command, Training, Habitat and Botanical shells and furnished interiors. The
Meshy reactor is reused in Engineering. The earlier generated exterior remains
available as source/reference; the active shell uses authored geometry so the
opening and walls match navigation precisely.

Rooms remain at their building's world coordinates. Walking through an automatic
sliding airlock changes inspection context without teleporting or unloading the
colony. The camera eases toward the room; front/side walls and roofs use a dithered
cutaway compatible with the Compatibility renderer. Hidden walls retain physical
collision. Direct directory visits and F entry/return remain immediate shortcuts.
Reduced motion uses immediate camera, door and cutaway changes and a static pose.

All six placed characters use the repaired Cybercat skeleton, with shared geometry
and role colors. These are variants of one character, not six bespoke sculpts.
Post-collision displacement controls walking; turns and idle/walk transitions are
smoothed. A small spine movement provides idle breathing. Mender, Surveyor and
Trainer occupy their authored rooms. Legacy illustrations remain the portraits
and fallback assets. Model definitions expose scene, scale, stride and tint.
Facial animation, foot/hand IK, running and task-specific work gestures remain
outside this delivered pass. Animation never claims that backend work occurred.

## Rebuild and review

Run `mise exec -- just world-colony-build` to rebuild all five shells, furniture,
collision resources and anchors from Blender and import them into Godot. It uses
Blender 5.2.1 and does not call Meshy or spend credits. The editable building
sources and `colony-layout.json` are under `art/meshy-blender/`; the connector
writes native scene and resource files from the same layout used for geometry.
Run `mise exec -- just world-seamless` to open Engineering, or
`mise exec -- just world-meshy-character` for isolated character inspection.

The [continuous colony evidence](../evidence/seamless-colony/README.md) records
failed baseline routing, corrected console clearance, native visual checks and
regression results. The five-building physics test covers walking to interiors,
consoles and back outside, airlock closing, cutaway state, no position jumps,
reduced motion, direct visits and no implicit command dispatch. Room tests retain
collision recovery, keyboard inspection, stale/offline activity and map controls.

## Face and helmet repair

The supplied rig assigned upper-head vertices to shoulder and arm bones. The
copied source remains in `assets-production/characters/cybercat-sentinel/blender/cybercat-source.blend`.
[The repair](../assets-production/scripts/repair_head_weights.py) makes vertices at world
Z >= 1.47 metres rigid to `Head`, with a smooth transition from 1.40 metres.
Weights below that region remain unchanged. This region is authored for this
source, not a general repair algorithm.

[Seven-pose measurements](../evidence/meshy-blender/head-weight-repair.json) cover
5,631 edges within the rigid region. Maximum relative edge-length strain fell
from 2.3324 to 0.0000706. This verifies rigidity, not anatomical perfection.
The source face texture, helmet shape and lower hair retain generation artifacts.
The final editable scene is `assets-production/characters/cybercat-sentinel/blender/cybercat.blend`.

## Production and cost

Blender is pinned to 5.2.1 for these sources; Godot remains 4.7.2. Blender MCP
inspected and copied the open source without saving over the user's original
project. Background exports use the official installed Blender executable;
the MCP background endpoint lacks its configured executable path.

The owner approved an 80-credit cap. Two Meshy-6 preview/texturing pipelines cost
60 credits total; the character repair used no credits. The API task list does
not expose the supplied web-workspace assets. The structure is a newly generated
interpretation, not a download of the original room. Prompts and cap are in the
[generation plan](../assets-production/batches/meshy-blender/generation-plan.json). The runner resumes
recorded IDs and refuses to retry uncertain submissions.

Raw downloads, task responses and thumbnails stay in ignored `meshy_output/`.
Shipping GLBs, extracted Godot textures, editable Blender sources and
[task IDs/hashes/costs](../assets-production/batches/meshy-blender/provenance.json) live in the branch.
The generated exterior ground platform is trimmed because the colony owns
paving. Downloads are unchanged. The interior exports seven material batches;
repeated exterior trim is batched by material. These choices are not measured
performance improvements.

## Remaining art scope

Unique character silhouettes and matching new portraits, hand contact with
consoles, facial cleanup beyond the repaired weights, and richer authored work
clips need a separate art pass. Completion requires native motion review and
pose/collision checks for each new asset. Al owns art acceptance; the implementation
assistant owns those checks when that pass is requested. This pass is not a
measured “10x” improvement, web qualification or deployment. Reverting resource
references and the continuous-room integration restores the previous presentation;
there is no data migration.

## Polished Engineering slice — September 7, 2026

The single-room review slice now uses concept-image references, Meshy design
images → untextured models → remesh → PBR texture, then local Blender fitting,
airlock cleanup and authored interior construction. The player and Mender use a
new rig with walk, run, idle and a Blender-baked console gesture. Actual travel
selects locomotion; local inspection selects the gesture without changing
backend activity. The remaining crew retain the earlier repaired Cybercat.

The batch consumed 140 credits; including the earlier 60-credit batch, the
recorded total is 200 of the approved 250 Meshy credits. See
[the review notes](../assets-production/batches/engineering-polish/REVIEW.md) and
[asset provenance](../assets-production/batches/engineering-polish/provenance.json) for the exact scope,
charges, source IDs, editable sources and review limitations. Rebuild locally
with `mise exec -- just world-engineering-build`; this reuses retained downloads
and does not call paid endpoints. New bespoke rooms wait for owner review.


The subsequent historical CyberCat Vanguard integration
replaces the player's Engineering suit with the exact supplied CyberCat model.
Its source had no rig or clips; rigging and idle cost 8 credits, with walk/run
included. Total recorded spend is now 208 / 250 (42 remaining). Mender retains
the Engineering suit. The earlier package remains available as a baseline.
