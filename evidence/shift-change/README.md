# Shift Change delivery

Status: proposed

Implemented on `codex/shift-change`. Local technical qualification passed;
Al's visual/play-feel acceptance remains open. This source-and-evidence handoff
includes no deployment. Existing backend/autonomous services were not changed, and persistent
memory remains disabled.

## Review the result

- [Occupied Habitat](final/shift-domestic/domestic-occupied-habitat.png)
- [Watch Surveyor leave home](final/operations-task-markers.png)
- [Reviewer working in Command](final/shift-journey/journey-console-arrival.png)
- [Reviewer back home with its report](final/shift-journey/journey-home.png)
- [Exact manifest](final/manifest.json)

Unsigned macOS ZIP:
`/Users/al/git/Starbase2/.local/reviews/shift-change/20260910-final-05/Starbase2-macOS.zip`.
SHA-256: `203feff42a60e31d810b835178dc231c74378aa172519d1516c554ca8f472fb1`.
The actual extracted executable was qualified outside the checkout. All 625
frozen world source files matched after qualification. Durable captures, reports
and logs are under `final/`; the large ZIP remains in the local review folder.

## Implemented behavior

Crew use seven reserved Habitat/Commons home anchors, travel continuously to
assigned workstations, and return home between assignments. Sit-down, seated and
stand-up clips use the exact selected Meshy rigs, with editable Blender sources.
Completion exposes evidence immediately even when a character is still travelling.
Offline/reduced states suppress cosmetic motion without changing retained records.

Habitat and Commons share a new domestic art kit. The central lounge, timber,
rug, textile details, plants, pendants and seats were checked in native Godot.
The Godot crew strip opens native inspection and explicit watching. L visits
Habitat; normal live startup enters it. No new Meshy credits were spent.

## Verification and limits

- All integrated world checks completed, with failures diagnosed and retained.
  [Integration record](integration/README.md) explains the corrected old spawn,
  travel-deadline, guide and capture assumptions.
- All 70 directed home/work routes and five physical round trips passed.
- Native command/operations HTTP fixture checks, keyboard interaction,
  compact large-text layout, watch/cutaway invariants and offline fencing passed.
- Every-frame protected-head checks and real front/side skin-contact review
  passed for the three rigs. Original source geometry/textures were preserved.
- Exact packaged domestic rehearsal passed in 7.119 seconds. The full
  seat → station → report → seat → offline/reconnect rehearsal passed in
  97.357 seconds. These are isolated fixture journeys, not production job runs.
- Final exported Habitat, Command, return-home and Watch images were inspected.
  The return framing has settled, unlike the earlier source rehearsal.

Original character textures retain dark, high-contrast armor details. Console
work reuses the existing standing gesture; sleeping needs, friendships,
synchronized conversation and cup-handling are not implemented. No measured
performance improvement or production readiness is inferred from screenshots.
The [remaining acceptance work](../../docs/living-autonomy.md) distinguishes
real production journeys and proposed exterior badges from this completed slice.

The world, world-QA and 3D-asset skills now capture the proven independent
visual review, bidirectional navigation, skin-contact, bone-bake, sparse-track,
material-default and native background-capture lessons. Rebuild from the retained
[production record](../../assets-production/batches/shift-change/README.md).
