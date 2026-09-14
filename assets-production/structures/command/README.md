# Command production source

Status: current living-colony world/repository checks passed; fresh standalone
qualification passed in `20260907-final-03`.
The previous remaining-structures artifact passed; its results below are historical
and do not certify the current authored interior changes.

Mission-planning table, analysis desks, communications racks and a roof antenna assembly. Operational context remains `review`; art does not dispatch work or certify status. Engineering and the current characters are preserved.
Generated equipment is decorative; authoritative state remains in existing UI.

The selected architecture uses the [v2 concept plate](concepts/architecture-v2.png)
created with built-in imagegen, then used by Meshy for the detailed exterior,
and a fitted whole generated hull around a **16 × 12 m** exact playable room.
The central local threshold is X=0, Z=1.55. Pads moved and the eastern/southern
shelf expanded by 12% for the larger colony layout; traversal still requires
native qualification.

The selected scripted source is `blender/command-polished.blend`, with collision
and interaction composition in `layout.json`. Fitted exterior source is
`blender/command-hull.blend`, exported as
`apps/world/assets/structures/command/hull.glb`. The original
`blender/review-building.blend` is the retained, unmodified baseline and is not
selected by this pipeline. Authored runtime media are `review-shell.glb` and
`review-interior.glb` in the same runtime directory. The connector composes them
in `apps/world/structures/exteriors/review-continuous.tscn` and
`apps/world/structures/interiors/review-continuous.tscn`.

The generated hull supplies exterior appearance. Authored `Roof` and `Cutaway`
preview surfaces are excluded from shipping architecture; `InteriorRevealBack`
shows the rear interior wall only after entry. Exact floor, collision, sliding
door leaves, entrance trim and interaction markers stay separate. A generated
doorway is decorative and never establishes physical clearance. Hull fitting
records applied scaling; visually inspect distortions, openings and cutaways.

Generated equipment dependencies: `mission-table, communications-array, analysis-console`. Their preparation reads retained paid GLBs
and actual task records from ignored `meshy_output/` and
`meshy_output/remaining-structures-ledger.json`. These are required local rebuild
inputs, not disposable cache, and are not automatically available in a clone.
The committed runtime exports support playing without regeneration.

See the [batch design](../../batches/remaining-structures/DESIGN.md) and
[generation plan](../../batches/remaining-structures/plan.json). The task has a
separate 1,250-credit allowance; historical charges are not part of it. The completed
13-model batch reconciles to 507 actual Meshy credits, 0 pending and 743 remaining.
The live ledger remains the accounting source of truth.

## Rebuild

From repository root, with Blender 5.2.1 and the pinned Godot available:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python assets-production/scripts/prepare_remaining_props.py
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python assets-production/scripts/build_remaining_structures.py -- --asset command
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python assets-production/scripts/prepare_remaining_hulls.py -- --asset command
python3 assets-production/scripts/connect_remaining_structures.py --asset command
mise exec -- godot --headless --path apps/world --editor --import --quit
```

The first command prepares all selected props and therefore needs their paid inputs;
use its `-- --asset <prop-id>` option to prepare only this structure's dependencies.
The batch recipe is `mise exec -- just world-remaining-build`.
These preparation/build commands perform no paid API calls. The connector fails
before writing if a selected runtime dependency is missing. Hydrate editable
Blender sources through Git LFS before source inspection.

The scripted architecture rebuild overwrites the selected `*-polished.blend`;
hull preparation overwrites `*-hull.blend` and `hull.glb`. It does not preserve manual Blender edits. Preserve a separate
working copy before editing; either incorporate accepted edits into the build
script, or explicitly export the edited source to the matching shell/interior
GLBs while retaining named door/cutaway groups and updating layout/collision,
then reconnect, import and qualify that result. Do not claim the scripted
rebuild reproduces manual edits until those edits are encoded in the script.

Review the actual native views and walk approach → doorway → console → exit.
Check collider clearance, keyboard/direct visits, reduced motion and unchanged
stale/offline semantics. Technical qualification and owner art approval remain
separate; this README does not certify either.

Final native exterior and interior images were visually inspected; no obvious
major hull/furniture clipping appeared in those views. Shared paneled rear walls
and generous floor space remain visible art judgments. Native stills do not certify
physical traversal or export qualification.

Validation: `mise exec -- just check-world` and `mise exec -- just check` passed.
See `evidence/world/remaining-structures/final/logs/check-world-final.log` and
`check-corrected.log`. The first standalone attempt exercised native journeys but
was correctly rejected for a motion contact-sheet image-format error. RGB8
conversion was added; the fresh `20260907-final-02` exact-artifact qualification passed. No owner
art approval or publishing is claimed.

## Current living-colony pass

See [living-colony design](../../batches/living-colony/DESIGN.md) for retained
interior architecture, material zones and equipment-based Console points. The
generic entrance kiosk is removed. Existing generated hulls/props are reused;
this pass has no new Meshy charges. Command's representative physical/native
slice passed before expansion; four-room visual review and corrected world/repository checks passed. Fresh
standalone export passed in `20260907-final-03`; the first attempt correctly failed source
hash binding after an intentional test edit. Engineering, characters and operational identities are preserved.
