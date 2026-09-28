# Crew workstation affordances

Status: proposed

Implemented locally with reviewed native work poses. Integrated qualification
and owner art acceptance remain separate.

Five authored control surfaces provide real geometry for crew hands, gaze and
control presses. They are scenery and animation targets. They do not dispatch
work, show invented task metrics, confer capability or establish operational
progress. Existing structured work records and keyboard controls remain the
source of operational information.

`apps/world/workstations/interaction_station.gd` is the editable, deterministic
Godot geometry source; no generated images, paid assets or external inputs are
needed. Static parts are combined by material, with separate physical key caps,
a control and a small contact cue. Each standing component is limited by regression to
12 mesh instances and 1,400 triangles, including tray/bezel bevels, mounting
fasteners and rear ventilation detail. These are geometry limits, not an FPS claim.

## Coordinate and interaction contract

The station origin uses the crew anchor's world X/Z and the actual sampled room
support height. The navigation plane is not assumed to be the visible floor.
Local +Z points toward controls, +Y is up and +X is the crew member's left.

| Crew role | Facing | Keyboard base above support | Support |
|---|---|---|---|
| repair / Rivet | North (-world Z) | 0.90 m | Brackets into Engineering wall console |
| review / Moss | West (-world X) | 1.13 m | Brackets into Mission Table side |
| gym / Mae | East (+world X) | 1.08 m | Grounded adjustable stand |
| watchkeeper / Wes | North | 0.90 m contact height | Seated, chair-arm keyboard at existing large console |
| reviewer / Prism | North | 0.80 m contact height | Seated, chair-arm keyboard at existing large console |

`configure(role, actor)` is called once. `contacts()` returns world `Transform3D`
frames named `left_key`, `right_key`, `screen` and `control`. `facing_point()` gives
the world-facing reference. Standing keys are 0.30 m forward and ±0.15 m sideways, fitted
to the selected rigs' actual reach. Their frames follow the physical caps' 9 mm
travel. The screen uses a static wiring schematic, not fake live data.

`present_contacts(weights)` receives the animation driver's measured contact
weights; there is no independent keyboard/blinking clock. Empty weights restore
neutral geometry, including on inactivity and reduced motion. Nonfinite weights
cannot poison transforms. The separate animation driver owns pose blending,
physical hand error checks, gaze, and which work records are eligible.

`footprint_rect()` returns the grounded stand's world X/Z rectangle, or an empty
rectangle for brackets attached to existing furniture. Stand bases span local
X=-0.30…0.30, Z=0.475…0.725; their actual bottom vertices are at support Y=0.
The base and post clear the actor's padded body. The shallow raised tray overhangs
that footprint for ergonomic reach; torso/skin clearance requires native review,
not merely a capsule check. Root integration registers the support with physical
collision and navigation from that same rectangle.

## Room composition corrections

Rivet's authored Engineering crew marker moved 0.35 m west to improve keyboard
visibility beside the lockers. The lower brackets remain within the wall-console
width. From the usual southeast view lockers still obscure some lower-body detail;
an above-shoulder view exposes the full connection and contact surface.

Command now uses the actual large consoles for Wes and Prism. Their former
freestanding terminals are removed. Both authored chairs face north; cushion tops
are 0.48 m above the 0.184 m platform (room Y=0.664), matching the actual seated
clips. Canonical seat references are X=±3.2, Z=-7.22. The actual 0.68 × 0.40 m
cushion is centered 0.14 m behind that reference, supporting the hips while
clearing the bent legs; `cushion_frame` and `cushion_size` expose its real volume. The full 1.00 × 0.70 m chair collision and
navigation proxy remains; the base radius is 0.30 m. The approach is 0.76 m north
of the cushion, outside both chair and desk bounds after 0.40 m navigation padding.
All 70 directed home/work routes passed with regenerated bounds.

`seated_console.gd` supplies `seat()` (world cushion frame, floor height, back frame,
cushion dimensions), `approach_point()`, and reachable chair-mounted keys. The
animation aligns its authored seat reference from the safe navigation point;
this is not a navigation teleport. The keyboard contact lies 0.39 m forward of
the cushion, at the role-specific heights above. The main console screen is a
gaze target; hands use the nearby keys and selector.

The supported tray is vertical while approaching. `set_seated_amount(1)` is sent
only after the body settles; the 0.28 s hinge motion must complete before
`seated_ready()` permits input. Standing requests stow it first and retain the
seat context through departure; `folded_ready()` exposes actual completion.
The two input accessories each use 10 mesh instances and 764 triangles, including
30 instanced physical keys, bounded by a 12-instance/1,800-triangle regression
limit. Their folded forward extent is 0.2745 m, leaving 0.4855 m to the approach
center (more than a 0.28 m body radius plus 0.10 m margin). These geometry
measurements do not establish a frame-rate improvement.

Reduced motion snaps the tray. Key feedback still comes only from observed hand
contact. Static scenery does not show invented progress or qualification.

Rebuild the chair composition offline with pinned Blender 5.2.1 LTS:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python assets-production/scripts/build_remaining_structures.py -- --asset command
.venv/bin/python assets-production/scripts/connect_remaining_structures.py --asset command
mise exec -- godot --headless --path apps/world --editor --import --quit
```

Existing generated equipment sources and paid ledgers are unchanged. The selected
Command blend, GLBs, layout and provenance are refreshed; the script remains the
reproducible source rather than an unrecorded Blender edit.

## Verification and retained failures

`workstations/test_interaction_station.gd` checks all four world frames, role
facing, physical key travel and moving contact targets, reset behavior, material/
geometry budgets, actual base vertices at the support origin, body clearance,
for the three standing roles. `test_seated_console.gd` checks imported cushion
vertices, retained chair/desk colliders and padded approach, exact reachable
contacts, folding readiness, physical key travel and reduced motion. Both passed
locally. Initial cushion measurement excluded bevel corners; the corrected sample
measures their actual top (0.663996 m), not only declared metadata.
Scoped Ruff lint/format and ty passed for the modified Command generator.

Native fit capture:

```sh
mise exec -- godot --path apps/world --max-fps 60 --script workstations/capture_fit.gd -- --working --output=/absolute/fresh/evidence/directory
```

This isolated standing-role fixture directly places Rivet, Moss and Mae at their work anchors and drives real
selected rigs from synthetic running records. It is a work-pose and furnishing
inspection, **not** physical-travel proof. The separate integration test exercises
actual home → workstation → home routes and authoritative state/reduced-motion
gates. Parent integration owns full world and fresh exported-artifact qualification.

Earlier closeups that hid Rivet behind a reactor/locker, cramped chair placement,
and the first actual-room height mismatch are retained. The isolated animation
stage did not reveal that raised room floors lift crew shoulders; the correction
anchors controls to sampled floor geometry and leaves arm lengths unchanged.


The prior standing-only native fitting evidence is retained in
[the workstation review](../evidence/world/workstation-contacts-20260928/README.md),
with all five normal/close images under `work-indexed-final/` and source hashes.
The bevel finish revealed an indexed/unindexed mesh-joining failure that initially
removed the casing faces. Final tests check outward normals, native primitive
winding and retention of both casings in the actual indexed render batch; native
images confirm the restored thickness. Failed intermediate images remain available.

The first seated native review caught a real 0.68 m cushion-depth collision
with lower legs. The rebuilt 0.40 m cushion preserves height, approach and full
chair collision bounds. Initial failures remain retained; exact cushion-volume
skin checks and final native views determine acceptance.

The seated Command environment passed focused geometry checks and independent
native fit review: [seated Command evidence](../evidence/world/seated-command-20260928/README.md).
Exact-volume skin audits found no cushion penetration in sampled seated transitions
after the physical depth correction. Full world/export qualification is owned by
root integration; the earlier standing images do not certify this newer arrangement.
