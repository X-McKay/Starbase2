# Remaining structures concept and assembly plan

Status: production plan, 2026-09-07. Native review and owner art judgment remain
separate gates. This document is not a claim that the planned assets are shipped.

## Inspected baseline

The current catalog contains five continuous structures. Engineering (`repair`)
is the reference milestone; Command (`review`), Training (`gym`), Habitat
(`habitat`) and Botanical (`greenhouse`) are the remaining four. The latter two
are scenery contexts with direct visits and no `interaction_kind` binding.
Preserve those IDs and semantics. The selected Vanguard, crew, 6 m/s movement,
zoom controls and expanded plateau are outside the art replacement scope.

The four current Blender sources come from `build_colony.py`: one rectangular
3.3 m wall template, 3.7 m roof, shared consoles and minimal distinguishing
furniture. The retained native colony capture in
`evidence/world/content-reorganization/native-package/colony.png` shows the gap:
Engineering has layered machinery and material variation; Command and Training
have broad blank walls and shallow roof boxes. The generator is a useful scale
reference, not a sufficient visual finish.

Read with [taxonomy](../../../docs/content-organization.md),
[lessons](../../../docs/world-production-lessons.md),
[experience](../../../docs/experience.md) and accepted ADRs 0002/0007.
The SPEC and experience direction retain proposed material; this is a local art
slice, not an implementation of new product operations.

## Shared language and dimensional contract

Use warm ivory ceramic armor, blue-black graphite recesses, brushed metal edges,
muted colored enamel, and small local service markings. Break broad surfaces into
structural bays, inset windows and purposeful service zones. Keep roughly half
the visible surfaces quiet. Bright color belongs at entrances, identity panels
and specific equipment; it must not imply backend success or progress.

The owner requested distinctive, compelling architecture and richer interiors
beyond the initial template pass. The selected second direction uses whole
Meshy-generated hulls derived from each structure's `concepts/architecture-v2.png`,
fitted around a larger exact authored room. Unique generated furniture remains
part of the design. The concept plates are art references, not dimensioned plans.

One unit is one metre. The selected layouts are now:

| Asset / room | Width × depth | Local threshold X/Z | Exterior identity |
|---|---|---|---|
| Command / `review` | 16 × 12 m | 0 / 1.55 | Layered observation bridge and communications crown |
| Training / `gym` | 16 × 12 m | 0 / 1.55 | Twin barrel vaults and violet simulation spaces |
| Habitat / `habitat` | 18 × 13 m | 0 / 1.55 | Rounded capsule volumes around warm shared living |
| Botanical / `greenhouse` | 17 × 12 m | 0 / 1.55 | Ribbed glazed conservatory and water-service spine |

Pads have moved to accommodate these footprints; the eastern and southern shelf
have expanded by 12%. Colony placement, paving and boundary collision require
joint native qualification. Engineering remains preserved. All doors are central
on local Z=1.55, with the exact authored 2.5 m opening and automatic sliding
leaves. Reserve a broad entrance and connected main aisle, using the actual
player collider to verify clearance. No generated doorway owns physical access.

Generated hull preparation fits measured mesh bounds to each room; this can
stretch the source, and the applied factors must be recorded in provenance.
The authored floor, exact walls/collision, door, interaction anchors, furnishing
and generated exterior remain separately controllable. Shipping architecture
excludes the superseded authored `Roof` and `Cutaway` preview groups. The rear
wall uses `InteriorRevealBack` so it appears only inside; generated hull meshes
use `Roof` prefixes to fade away on entry. Distinct entrance trim can remain
under its own cutaway prefix. This prevents a plain preview box or rear wall
from showing through a narrower generated hull.

## Selected structure compositions

Command uses a fitted observation-bridge hull and separate roof communications
array. Inside, a 3.4 × 2.4 × 1.2 m maximum-fit mission table sits on the center
plinth. Four 3.6 × 1.1 × 2.3 m maximum-fit analysis consoles furnish the rear and
side walls; chairs, lockers, briefing bench, floor accents and low perimeter walls
complete the room. Side consoles face inward. Enlarging the original small table
and rear consoles corrected the sparse first interior. Final native stills show a readable furnished room and improved entrance
backing; full world/repository checks and the final standalone macOS qualification passed.

Training uses a fitted twin-vault hall with violet accents. Two generated
simulation stations and two resistance benches create paired practice zones,
with authored storage, exercise frame and wall-mounted equipment. Simulator
maximum fit is 2.2 × 2.2 × 2.6 m; resistance bench fit is 2.4 × 1.2 × 2.6 m.
These are decorative physical practice spaces; paired equipment cannot imply
live baseline/candidate evaluations without authoritative records.

Habitat uses a fitted rounded capsule exterior with warm window bands. Three
3 × 2 × 2.5 m maximum-fit sleep capsules furnish the rear, a 2.6 × 0.8 × 2.1 m
maximum-fit galley faces the room from the side, and authored dining/seating
furniture provides shared amenities. Its operational room ID remains `habitat`,
with scenery-only inspection. The concept's stacked exterior windows do not
create a second playable storey; the runtime room has one floor.

Botanical uses a fitted arched conservatory hull with a water-service spine.
Four generated hydroponic racks occupy two authored cultivation beds. Rack
maximum fit is 2.2 × 1.25 × 2.2 m; each is turned 90 degrees and placed with
rearward clearance from the inspection terminal. A generated 2.7 × 1 × 1.8 m
maximum-fit botany bench supplies research detail, alongside authored water
reservoir and pipework. The transparent-looking generated glazing includes
plant imagery; native review must judge its contrast against the separate real
interior. Its room ID remains `greenhouse`, with scenery-only inspection.

All dimensions above are preparation fit limits, not measured final extents;
uniform scaling can leave one or more dimensions smaller. Real floor layout,
collider dimensions and navigation paths come from current per-asset layouts.
No still image establishes collision clearance or proves traversal.

## Generation and reproducible assembly

The selected set includes four fitted whole-structure hulls and unique equipment:
mission table, communications array, analysis console, simulation station,
resistance bench, frontier galley, sleep capsule, hydroponic rack and botany lab
bench. Built-in imagegen produced the ambitious exterior/cutaway concept plates. Meshy
used them as design references for isolated hull generation; Blender then fit
and prepared downloaded geometry for Godot. Whole hulls derive from those plates;
equipment inputs remain isolated objects without people, surrounding rooms or
baked operational indicators. Inspect geometry and PBR channels before any
additional purchase. Static structures and furnishings need no rig or animation.

The new authorization is **1,250 credits**, independent of the historical
208-credit milestone. As reconciled for the completed 13-model batch, actual
Meshy charges total **507 credits**, pending reservations **0**, and remaining
authorized budget **743 credits**. Image design stages are included in that
Meshy total. Keep the task ledger as the accounting source of truth, and
reconcile an uncertain submission before retrying. The generation plan and dimensional targets do not constitute a provider price
quote. Room dimensions come from the selected authored layout; prop fit limits
come from preparation and must be distinguished from measured output bounds.

Use separate background Blender files. Save editable per-asset `.blend` sources
under `assets-production/structures/<asset-id>/blender/` and runtime GLBs under
`apps/world/assets/structures/<asset-id>/`. An independently reusable hero prop
may instead use matching `props/<asset-id>` directories. Preserve original paid
downloads and record source/task IDs, normalization, measured triangles, texture
sizes and hashes. Keep texture sizes and geometry measured in each preparation record; measure
native results before any performance claim or further optimization.

Keep semantic geometry groups: `Floor`, generated `Roof*`, entrance `Cutaway*`, `DoorLeft*`,
`DoorRight*`, `InteriorReveal*`, and furniture. `station.gd` discovers these
prefixes to move leaves and fade/reveal materials. Prefix every generated roof
mesh appropriately after import, preserving its PBR textures. Author collision
and navigation separately as matching box rectangles; never use an arbitrary
generated silhouette as the navigation envelope. Retain opaque shadow geometry
only when it does not become a second visible roof.

The selected `build_remaining_structures.py`, `prepare_remaining_hulls.py`,
`prepare_remaining_props.py` and `connect_remaining_structures.py` form the
rebuild pipeline. Build authored layouts first, then fit each generated hull,
prepare equipment and reconnect selected rooms. The older `build_colony.py` and
`connect_colony.py` remain baseline recipes and can overwrite selected layouts.
The remaining-structures recipe must reapply the current selected resources. Preserve `repair` and its
selected resources byte-for-byte. Make the broad rebuild reapply the selected
remaining structures as it currently reapplies Engineering. Source rebuilds
must remain offline and free of paid calls.

## Completion evidence

For each structure retain native closed exterior and interior cutaway captures,
then walk approach → doorway → interior → console → exit with real physics.
Verify side-route collisions, doorway opening, camera occlusion, keyboard and
direct visit, reduced motion, and unchanged stale/offline semantics. Check logs
for errors even after exit zero. Run focused checks before repository world and
full checks. Freeze world sources during standalone macOS qualification, using
the current Launch Services harness and exact source/artifact hashes.

The production task owns correction of blocked routes, exposed furnishings,
missing PBR channels and rebuild selection drift before handoff. Owner judgment
of visual polish remains open until the delivered native review is accepted;
no screenshot or automated technical pass alone closes that judgment.

## Native visual assessment

The final exterior and interior captures for all four rooms were independently
viewed under `evidence/world/remaining-structures/final/native/`. Exterior
silhouettes are distinct; no obvious major hull/furniture clipping appeared in
those views. Botanical glazing is opaque and textured, with foliage imagery,
rather than a transparent view into the actual room. Interiors remain more
restrained than the concept plates: shared paneled rear walls and generous clear
floor are most apparent in Training and Habitat. The first Botanical capture showed an unsupported water-service pipe; the
builder now routes it toward the bench with a vertical downleg. A scattered
outcrop near the Botanical approach also moved from (12, 35) to (10, 42) after
a full-world route check exposed the conflict; the corrected full world suite passed. These are
concrete owner-review art follow-ups; still images do not certify physical
journeys, accessibility states or the exported package.

## Verification status

Full world checks passed (`final/logs/check-world-final.log`) and repository
checks passed (`final/logs/check-corrected.log`) under the remaining-structures
evidence milestone. Repository results include 34 Rust and 76 Python tests,
lint/type/contract checks and documentation checks. The first exported build's
journeys ran, but qualification correctly failed on a motion-contact-sheet image
format error. The capture source now converts images to RGB8; a fresh standalone
qualification passed in `20260907-final-02`. The corrected Botanical pipe was independently
inspected in that first export's interior capture and visibly connects tank to
bench services. No successful export result is inferred from successful journeys.

Final qualification: the unsigned macOS `20260907-final-02` review passed, with
exact source/artifact hashes in its manifest and an inspected nonblank 12-frame
motion contact sheet. Full world checks preceded the capture-only RGB8 fix;
the fresh standalone run covers that final capture change. This establishes
local technical qualification, not owner art approval or deployment readiness.
