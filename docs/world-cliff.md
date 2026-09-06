# Aster colony: exposed cliff shelf

Status: accepted

Date: 2026-09-05. Scope: native terrain geometry, boundaries and presentation.

The later [geology refinement](world-geology.md) replaces the striped material
and adds deeper rock formations while preserving this shared shelf boundary.
Its connected-coast extension supersedes the finite rear wall with decorative
mainland terrain. The subsequent natural-outline pass rounds the plateau into
headlands and coves and updates the shared render/collision/navigation boundary.

## Implemented landform

The owner requested a near-side cliff drop with a rock wall behind the colony,
in place of the surrounding rock barriers. The former infinite ground plane,
rectangular survey curb and near/side boulder rows are removed. The colony now
occupies an irregular shelf: a triangulated red-soil cap, a continuous cliff face
descending roughly 24 world units, broken buttresses beneath the rim, and a cool
lower canyon with distant rock columns. A connected rear escarpment rises into
high ground and extends down into the canyon. Static haze increases with depth.

This is original editable geometry inspired by the supplied references; no image
assets were copied. The red terrain materials, crew and colony districts remain.
The map overview frames the full vertical landform. Normal follow and reduced-
motion room cameras retain their existing controls. The lower canyon is scenery;
falling, climbing, swimming and lower-level traversal are not implemented.

## One edge definition

[geography.gd](../apps/world/geography.gd) owns the authored shelf polygon used by
rendering, the top collision mesh, perimeter collision segments and route
clearance. Navigation rejects points outside the shelf or within 0.4 units of
its edge. Physical movement stops at the rim, including oblique corners.
The route grid includes the irregular shelf tips. Contact with the physical rim
can round into a padded grid cell; routing selects a nearby clear start only when
the connecting segment stays on the shelf and outside obstacles. A physical
contact-and-return test covers this case.
There is no visible railing or curb. All existing crew/district journeys and
landmark avoidance remain available; essential controls still have non-spatial
keyboard and journal equivalents.

The original route grid accepted a point over the new corner cutout. That failure
was reproduced before implementing the shape, and is retained in
[boundary-before.log](../evidence/world-cliff/boundary-before.log). Tests now check
that cutout plus real physical movement against the near and angled cliff edges.

## Evidence and limitations

- [Previous rock barriers](../evidence/world-cliff/before.png).
- [Finished shelf overview](../evidence/world-cliff/overview-final.png).
- [Real walk to the overlook](../evidence/world-cliff/overlook-final.png).
- [Compact larger-text stale fixture](../evidence/world-cliff/stale-compact.png).

The first render established the drop but exposed an overly smooth cliff face and
a rear wall ending above the lower canyon at its sides. Broken below-rim columns
and a full-height rear wall address those issues. An inferred-type compile error
was corrected; initial failures and captures remain in the evidence directory.

[Validation details](../evidence/world-cliff/validation.json) retain actual checks
and short native frame samples on macOS Apple M5 / Godot 4.7.2 Compatibility.
Both `just check-world` and `just check` passed (27 Rust tests, 16 Python tests,
lint/contracts and 33 Markdown documents). The native overlook walk reached its
target. The overview observed 16.67 ms median and p95 frame intervals at the
60 FPS cap over 150 post-warmup frames.
These capped observations do not establish performance improvement or other-
platform qualification. The walkable surface remains flat and finite. Lower
terrain, depth haze and vegetation are static decorative presentation, not live
agent activity or a resource system.

No agent work, inference, deployment, schema migration or authority change was
performed. Live captures display previously retained core records. Recovery is
reverting presentation/navigation files; no data rollback is required.

Owner: Starbase2 development. Slope traversal, falling/recovery and authored
lower-canyon exploration require their own navigation and recovery acceptance
conditions. Existing animation, audio, interiors and platform work remain in
[the playable-world completion plan](world-playable.md).
