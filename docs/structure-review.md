# Colony structure review

Status: proposed

Date: 2026-09-06. This document records the initial design review. The subsequent
[building catalog milestone](building-catalog.md) implements the hangar journey
and scalable asset contract; the broader structure recommendations remain proposed.

## Evidence and scope

Reviewed Starbase-lite main at `a3c355929c3c3b258de053818b82d0eba4aba5ee`
(Merge pull request #34, feature/layout), verified against GitHub main with
`git ls-remote`. Compared source and retained screenshots with Starbase2's
[colony overview](../evidence/world-uplands/overview.png),
[workshop interior](../evidence/world-rollout/workshop.png),
[exterior builder](../apps/world/station.gd) and
[room builder](../apps/world/colony_room.gd). Neither game was launched during
this review; this establishes design and implementation differences, not current
interaction correctness or performance.

Starbase-lite's [station registry](https://github.com/X-McKay/Starbase-lite/blob/a3c355929c3c3b258de053818b82d0eba4aba5ee/starbase-ui/godot/data/stations.json)
contains six interior buildings: Archive, Defense Ward, Habitat Dome, Ops Deck,
Reactor and Scriptorium. Mail Room, Plaza Ticker and five Listening Posts are
exterior entries. The [world specification](https://github.com/X-McKay/Starbase-lite/blob/a3c355929c3c3b258de053818b82d0eba4aba5ee/docs/design/station_world_spec.md)
also proposes Lighthouse, Vault, Dojo and Workshop concepts; their presence in
that draft does not establish them as shipped structures.

The strongest reusable ideas are architectural identity, districts and furnishings
that explain purpose. Its [Ops Deck](https://github.com/X-McKay/Starbase-lite/blob/a3c355929c3c3b258de053818b82d0eba4aba5ee/starbase-ui/godot/src/station/ops_deck.gd)
has racks, a holotable, a situation display and chairs; its Scriptorium uses a
lectern and pipe wall. These are meaningfully different places. The
[retained layout capture](https://github.com/X-McKay/Starbase-lite/blob/a3c355929c3c3b258de053818b82d0eba4aba5ee/docs/evidence/polish/layout-after.png)
shows a similarly varied skyline.

## Diagnosis

Our materials and planetary terrain provide a coherent foundation. However, all
three main buildings use the same rectangular shell and entrance, distinguished
mostly by rooftop accessories. All three rooms share a square footprint, back
consoles and central desk. In the overview they form a small straight row on a
rectangular plaza. More surface detail alone will not resolve that repetition.

Keep the space-colony palette and established textured-geometry/sprite approach.
Vary whole building proportions, rooflines, openings and room composition. Reuse
materials and construction parts without requiring identical architecture.

## Recommended structures

| Place | Exterior and setting | Interior and useful purpose |
|---|---|---|
| Workshop → Engineering Hangar | Broad asymmetric hangar near the landing pad; segmented roof, crane rail, side utility annex and service apron | Repair cradle as the focal object, tool wall, parts storage and clear working aisle. Existing repair controls and evidence remain explicit; machinery is scenery unless backed by records. |
| Command → Survey Command | Elevated bridge with panoramic glazing, offset sensor mast and a sheltered entrance | Central briefing table, curved stations and observation windows. Existing review findings, duties and run inspection; decorative maps must not imply live cluster telemetry. |
| Trial Hall → Evaluation Lab | Twin volumes joined by a distinctive ring and observation gallery | Paired baseline/candidate bays and a shared comparison display. Reproducible trials and retained results are the reason to visit; inconclusive and regression remain visible. |
| Habitat and greenhouse → Commons | Connected low pods, warm windows, airlocks and a garden court | Initially environmental storytelling. A future accessible crew directory/lounge can justify an interior; do not invent oxygen, supplies or morale simulations. |
| Archive + Scriptorium → Research Archive annex | Compact vertical stacks with warm recessed glazing beside the lab | One evidence-reading space for existing reports and history. Avoid separate buildings for repository analysis, memory and storage; memory curation remains future functionality. |
| Listening Posts + Lighthouse → Signal Beacon | One coastal landmark and a few smaller instruments, integrated into the rock | Potential entry to existing duty/run records. Source freshness or worker-health lights require their own authoritative measurements; a decorative beacon is not proof of operational health. |

The predecessor's Mail Room can become a small dispatch board near Command,
reusing the journal and duty controls. A standalone routing building, separate
Reactor interior and Defense Ward should wait for a distinct useful interaction.
No proposed place requires a new backend service or datastore.

## Settlement composition

Organize an engineering yard beside the landing pad, a compact command/research
group toward the uplands and a warmer residential court around the habitat.
Stagger buildings along the terrain instead of retaining one lineup. Use one tall
landmark, one broad industrial form and several lower support volumes. Tune their
scale against the crew and gameplay camera before changing footprints.

Routes should connect visible doors through entrance aprons, then join a clear
main path. Put cargo, utility runs and retaining walls where their placement makes
sense; keep the travel lane quiet. Lighting and wayfinding should reinforce these
districts. Operational permission boundaries remain in policy, independent of
fences, doors or where a character stands.

## Implementation follow-through · 2026-09-06

The [building catalog rollout](building-catalog.md) now implements the hangar
journey and five distinct exteriors with separated districts. Habitat and
greenhouse remain separate purpose-specific structures rather than the proposed
combined Commons. The catalog accepts PNG artwork with independent collision and
door anchors, superseding the geometry-first recommendation below. Archive, beacon
and additional interiors remain proposals.

## Original implementation milestone

Finish the Engineering Hangar exterior, entrance, interior and surrounding yard
as one complete journey. It exercises the existing repair interaction and the
[art production contract](art-production.md) without adding a speculative system.
Use authored Godot scenes with shared trim, door, window, roof, floor and prop
parts; retain real geometry for silhouettes and use PNG detail where appropriate.
No new editor framework is needed.

Owner: Starbase2 world implementation, with Al reviewing the visual result.
Completion requires recognizable architecture at overview and walking zoom;
consistent crew scale and texture density; coherent exterior/interior identity;
unblocked doors, furniture routes and keyboard/direct access; and unchanged
unknown/stale/failure/evidence behavior. Capture the same exterior and room views
before and after, run affected world checks and measure frame cost before making
performance claims. Then apply the proven kit to Command and Trial Hall. Additional
interiors remain deferred until a distinct interaction and these art gates justify
them. This original review was a proposal; the follow-through above records what is now implemented.
