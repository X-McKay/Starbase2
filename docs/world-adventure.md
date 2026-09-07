# Aster frontier: space-adventure art direction

Status: accepted

Date: 2026-09-05. Scope: native world presentation and character interaction.

## What changed

The owner asked for a more adventurous science-fiction RPG, with stronger crew
art inspired by classic EVA suits, powered armor and armored space sentinels.
Aster now has an armored engineering hangar, a circular command bridge, and a
trial hall with a decorative expedition-gate landmark. Airlocks, panoramic light
bands, machinery, floor conduits, a cooler deck palette and a ringed gas giant
replace the earlier village-like silhouettes. The gate is scenery, not an
implemented teleportation or mission-dispatch mechanic.

The crew now uses project-local generated raster artwork:

| Identity | Cosmetic appearance |
|---|---|
| Operator | Expedition captain: silver-blue hair, navy suit, teal cape |
| Surveyor | Classic EVA explorer: off-white pressure suit, gold visor, life support pack |
| Mender | Copper/purple powered exosuit, green visor, mechanical tool gauntlet |
| Trainer | Ivory sentinel armor, graphite undersuit, asymmetric blue shoulder |

These are appearances, not changes to agent prompts, capabilities, credentials,
qualification or progression. Inspector portraits use the same atlas regions as
the world. Characters are taller and use sprite-sized mouse hit areas; clicking a
helmet reaches the same inspector as keyboard interaction. Ambient strolls have
rest periods, and reduced motion keeps crew still. Motion never certifies work.

`just world` runs the game. `just world-crew` opens the clearly labeled character
art gallery. Existing native repair, cancellation, evidence and journal paths
remain available. No backend schema, authentication or service boundary changed.

## Assets and provenance

The built-in image-generation tool produced the crew artwork; source prompts and
correction history are retained in
[crew-provenance.json](../apps/world/assets/characters/frontier-crew/crew-provenance.json). The standing atlas
is [crew-adventure.png](../apps/world/assets/characters/frontier-crew/crew-adventure.png); Godot loads it directly rather than displaying a screenshot mockup. Original vector
textures, reusable geometry and the sky shader remain editable source.

The standing source has sixteen poses, four facings for each identity. Travel currently uses procedural bobbing, with no separate foot-stride artwork.
A consistent multi-frame walk cycle remains unfinished. Atlas boundaries are calculated from actual image dimensions rather than
assuming generation returned the requested resolution. Region validation checks
alpha, bounds, nonempty characters and clipping of opaque pixels.

The initial walking output had an opaque black background; two subsequent
attempts baked in checkerboards. A fresh generation passed alpha checks but changed
character identities and failed left-facing direction review. All walking candidates
were rejected and moved out of runtime assets into `evidence/world-adventure`.
Only the approved standing/facing atlas ships; passing technical asset checks alone
was insufficient for visual acceptance.
The source generator also returned taller proportions than the initial prompt's
three-head target; those heroic silhouettes were accepted as a visual choice.

## Evidence and remaining work

The [crew gallery](../evidence/world-adventure/crew.png) shows the exact front-facing
atlas regions used by the game. A reproduced helmet-click regression drove the
new projected sprite hitbox; the keyboard/mouse journey passes with the new
silhouettes. Compact larger-text and stale-state rendering was visually inspected.
The final [native outpost capture](../evidence/world-adventure/outpost.png) reads
existing local core records; the [walking capture](../evidence/world-adventure/walk.png)
reaches Mender through real navigation and physics. The
[compact inspector](../evidence/world-adventure/stale-compact.png) uses an explicitly
labeled stale-state fixture at 960 × 720, with larger text and reduced motion.

Validation on macOS Apple M5 / Godot 4.7.2:

- `just check` passed: 27 Rust tests, 16 Python tests, lint, contracts and docs.
- Final `just check-world` passed: authoritative state projections, navigation,
  all 16 accepted atlas regions, keyboard/mouse interaction and HTTP command
  failure/reconciliation fixtures.
- Native captures at 1280 × 800, capped at 60 FPS, observed 16.67 ms median and
  18.06 ms p95 frame intervals; these short local samples are not a comparative
  benchmark or other-platform qualification.

Exact results, asset hash and limitations are retained in
[validation.json](../evidence/world-adventure/validation.json). No operational
agent work was dispatched for this visual pass; live captures display previously
retained results. There are no deployment or data-migration requirements.

This is an art/interaction upgrade, not implementation of combat, space travel,
interiors, equipment mechanics or a new mission system. Broader animation sets,
sound, persistent decoration, gamepad support and other-platform qualification
remain owned by Starbase2 development under the existing
[playable-world completion conditions](world-playable.md). Before expanding those
systems, review the crew at gameplay zoom and develop more coherent environment
props to match the higher-detail character art.
