# Aster colony: planetary basin

Status: accepted

Date: 2026-09-05. Scope: local native Godot presentation and exploration.

The subsequent [red-planet surface pass](world-surface.md) supersedes the initial
muted surface palette and adds mineral-pool and standing-stone landmarks.

## Implemented

The owner requested a larger planetary settlement with the feeling of establishing
a new colony. Continuous earth, muted alien groundcover, layered rocky escarpments
and compacted trails replace the floating terrace and its railings. The existing
three working rooms and four crew remain the civic center. New scenery includes
an expedition shuttle and landing pad, solar field, survey mast, first habitat,
botanical module, crystals and two marked reserved building sites.

Navigation spans 79 × 63 world units, up from 24 × 15: approximately fourteen times
the bounding area before subtracting obstacles. The basin has a visible survey
curb and escarpments at its limits. Ground beyond the boundary is scenery, not an
infinite explorable planet. The traversable surface remains flat; distant terrain
adds visual elevation without claiming slope navigation or climbing.

`just world` opens the colony. WASD/arrows and click-to-walk explore it. The camera
follows by default; C toggles a room camera. Reduced motion uses immediate room
changes and still crew, so it never leaves the operator beyond a fixed viewport.
M or the Map button toggles a wide colony overview; `just world-map` opens that
view directly. Wheel zoom remains available in walking view. Crew selection,
E, 1/2/3, Tab and the independent journal preserve access without travel.

The added structures, vehicle, vegetation and reserved plots are cosmetic scenery.
They do not dispatch construction, simulate food or power, award XP, grant
permissions or represent operational resource telemetry. The help panel says so.
Core snapshot freshness, retained evidence, native repair/cancel commands and all
agent behavior are unchanged. There is no new service, datastore or migration.

## Implementation and evidence

Navigation and scenery share explicit prop footprints, inflated for the character
radius by the route planner. Real colliders use the uninflated rectangles. Tests
check reachability to landing, habitat, expansion and survey districts, physical
boundary/greenhouse collision, map toggling and reduced-motion room changes.
The original failure to reach those districts is retained in
[routes-before.log](../evidence/world-colony/routes-before.log).

Terrain, trail meshes and faceted rocks are original editable code. Existing crew
art and its provenance are unchanged. Visual review rejected the first excessively
regular boulder perimeter and overly contrasting ground palette; a subsequent
mesh-winding error was visible in the native capture and corrected. Intermediate
captures and failed checks are retained alongside final evidence.

Final captures and measurements on macOS Apple M5, Godot 4.7.2 Compatibility:

- [Colony overview](../evidence/world-colony/overview-final.png).
- [Normal gameplay](../evidence/world-colony/colony-final.png).
- [Physical journey to the landing site](../evidence/world-colony/landing-final.png).
- [Compact stale fixture, larger text and reduced motion](../evidence/world-colony/stale-compact.png).

[Validation details](../evidence/world-colony/validation.json) retain commands,
results and per-capture engine frame samples. These are short 60-FPS-capped local
observations, not comparative performance evidence or other-platform qualification.
Both `just check-world` and `just check` passed (27 Rust tests, 16 Python tests,
lint/contracts and 31 Markdown files). Normal and overview captures observed
16.67 ms median and p95 frame intervals at the 60 FPS cap.
No operational agent work or inference was dispatched in this visual pass; live
captures display previously retained core records.

## Remaining work

Owner: Starbase2 development, with Al reviewing the colony direction. Construction,
resource gameplay, enterable habitat/greenhouse, terrain elevation traversal and
persistent expansion remain unimplemented. Before implementing construction,
agree on its useful relationship to agent configuration and evidence, preserve
non-spatial access, and test persistence and recovery without gameplay granting
authority. Continue the animation, sound, comfort and platform completion gates in
[the playable-world record](world-playable.md). Full foot-stride character cycles
remain unfinished as recorded in [the adventure pass](world-adventure.md).
