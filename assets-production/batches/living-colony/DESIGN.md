# Living colony frontend

Status: implemented for local review; corrected world and repository checks
passed. Final unsigned macOS standalone qualification passed; owner art approval remains open. Branch `codex/living-colony-frontend`, base `9dc417b`.
Owner art approval remains open. This follows the qualified remaining-structures
milestone; it does not retroactively change that milestone's evidence.

## Direction and asset chain

Make the colony an inhabited place rather than isolated product models on pads.
The [arrival storyboard](concepts/command-arrival.png) and its
[exact prompt](concepts/prompt.txt) were produced with built-in imagegen. They
provide composition direction, not a literal screenshot target or measured plan.
Reuse the four Meshy hulls and nine equipment models from
[remaining structures](../remaining-structures/DESIGN.md). This milestone spends
**0 new Meshy credits**: the existing batch remains **507 actual, 0 pending,
743 remaining** under its separate 1,250-credit allowance. No paid generation
belongs in an ordinary source rebuild.

Blender now authors the architecture that remains visible after the generated
hulls fade. Command retains angular bridge sections and a mullioned observation
band; Training retains twin vault sections and paired practice zones; Habitat
uses warm wood, linen, sleeping-alcove wings and a dining area; Botanical retains
conservatory arches, glazing sections, overhead irrigation and richer growing
beds. Floor material zones stay flush; substantial additions occupy existing
obstacle envelopes or remain above player head clearance. Engineering and current
characters remain preserved.

A 10 × 7.1 m commons occupies the reserved plot centered at (-7, 23), providing
a shared destination between structures. It must be verified with the actual
colony paths, landmarks and camera rather than treated as spare empty land.

## Operator journey

Godot presents quieter HUD surfaces, authored room cameras and descriptive room
guides. The shared entrance kiosk is removed from the four interiors; interaction
now leads to each room's meaningful equipment or shared space:

| Room ID | Primary Console marker, local X/Y/Z | Focus |
|---|---|---|
| `review` | 0 / 0 / -2.45 | Mission table |
| `gym` | -3.4 / 0 / -2.55 | Left simulator approach |
| `habitat` | 0.5 / 0 / -3.55 | Communal table |
| `greenhouse` | 0 / 0 / -8.05 | Research-bench approach |

The markers clear the existing furniture boxes expanded by the 0.28 m player
radius in a source-layout check. This does not replace physical journeys.
Crew and WalkTarget locations are preserved. Room IDs and backend authority
remain unchanged: Habitat and Botanical remain scenery contexts. Guides explain
the room without claiming live work. Optional audio and decorative breeze are
ambient presentation; reduced motion suppresses decorative motion. They never
assert success, agent reasoning or operational progress.

## Rebuild and review

The builder is `assets-production/scripts/build_remaining_structures.py` with
`-- --asset command` for the representative slice, or no asset filter for all
four. Sources remain per-structure `blender/*-polished.blend`; generated hulls
and props retain their previous selected sources. The complete milestone recipe
is `mise exec -- just world-living-build`. The complete offline background
Blender recipe ran without errors and preserved selected hulls/equipment. The
96-file Engineering/character preservation check passed.

Scripted rebuilds overwrite their generated editable outputs. Encode accepted
manual changes in the scripts or explicitly export and requalify a separately
maintained edited source; do not claim automatic preservation of manual edits.

The first Command slice passed its native physical journey, console, cutaway,
direct-visit, reduced-motion and no-dispatch checks and was visually reviewed
before extending the approach. All four native interiors were inspected; the
corrected world suite and repository checks passed. The first standalone attempt
passed journeys/motion/native checks but was correctly rejected because source
hashes changed during an intentional test correction. Final standalone export
qualification passed in `20260907-final-03`. See
[living-colony evidence](../../../evidence/world/living-colony/README.md).

The commons includes decorative foliage breeze, roof-slat cutaway on approach,
a dedicated arrival camera and optional room ambience, muted by default. These
are presentation features, not simulated operational progress. Reduced motion
suppresses the breeze and uses immediate presentation transitions.

Training's retained middle vault sections now connect back to the rear structure
with high longitudinal beams. Botanical's initial box-shaped edge foliage was
replaced with folded pointed blades; exported interior views show both
corrections. Remaining art judgments are Habitat's table partly hidden by chairs
at its camera angle, intentionally opaque textured glazing, and the overall
level of furnishing. Owner art approval remains open.

Qualification correction: the second export was intentionally stopped after
independent review found leaf back-face culling. A dedicated two-sided leaf
shader now handles the three actual foliage surfaces; its focused material
check and living journey passed. The foliage test is registered in the suite.
The full world pass preceded this narrow fix. The third export, `20260907-final-03`,
qualified against frozen sources. Production provenance records
221 selected inputs and 96 preserved files; the export manifest separately owns
complete source/artifact binding. Reduced motion suppresses decorative breeze;
steady optional audio is independent and remains muted by default.

Final result: `20260907-final-03` qualified with exit zero. The actual four rooms,
guides, wide/compact board, motion strip and commons were inspected; leaf coverage
and compact labels are corrected. Durable artifact/source binding and measured
frame/startup results are in the [evidence record](../../../evidence/world/living-colony/README.md).
No performance improvement or owner art acceptance is claimed.
