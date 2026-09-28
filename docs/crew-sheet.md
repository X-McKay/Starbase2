# Evidence-first Crew sheet

Status: proposed

## Implemented view

Every existing crew dossier has a **Crew sheet** tab. Open Crew, inspect a member,
then select the tab with pointer or keyboard. This is the first presentation slice
of the [autonomous RPG direction](autonomous-rpg-research.md#crew-sheets-that-mean-something),
not completion of its progression and qualification system.

The sheet separates lifetime progression, current capability, registered builds,
historical qualifications and operational clearance. It uses the existing Core
operations snapshot; opening or navigating it never dispatches work.

- Rivet shows the Core ledger's Level and lifetime XP only when its persistent
  identity is `mender`. The existing synthetic-practice rule remains provisional
  under [ADR 0004](adr/0004-isolated-repairs-and-progression.md). Other crew show
  missing ledger data explicitly. Switching crew cannot transfer Rivet's XP.
- All eight stats have visible cards: Agility, Speed, Constitution, Efficiency,
  Perception, Wisdom, Precision and Cooperation. Current and best are unassessed:
  the current API has no admitted rating records or comparable historical bests.
  Constitution describes endurance; Efficiency describes resource use.
- Class and Subclass are not reported. Role names are not silently converted to
  permanent Class assignments. The mapping and assignment contract remain open.
- Skill manifests are distinguished from typical role workflows; both keep rank
  unassessed. Registered builds retain their exact digests. Registration does not
  establish an active build or equipped tool, Procedure or Run book.
- Historical synthetic qualifications retain exact build, scenario and run IDs.
  They cannot qualify a replacement build. The existing Evidence route remains
  available; the sheet does not claim that every historical run is present in
  the bounded current assignment list.
- Snapshot observation time, fixture provenance and disconnected last-known data
  remain visible. Operational clearance is separate from XP, Level and skills.

The component uses static cards with no operational animation. Cards participate
in keyboard focus, receive an orange focus border and scroll into view. The
layout has two columns where space allows, falling back to one below 470 pixels
of content width. Wide view retains the crew portrait; compact view preserves
all content in the existing scrollable workspace. Existing Overview, Evidence
and Practice navigation indexes remain unchanged.

## Evidence and limits

Focused Crew sheet, Crew guide and console HUD checks passed. Native Godot 4.7.2
captures on Apple M5 at 1280×800 and 800×640 with larger compact text were inspected:
all eight stat cards, build/history distinction, visible keyboard focus, fixture
and disconnected states, crew switching, and the keyboard route to Evidence.
The source-checkout review is retained in
[local evidence](../evidence/world/crew-sheet-20260927/README.md).
The parent integration pass owns the full world suite. No standalone export,
screen-reader support, platform expansion or performance improvement is claimed.
Owner visual acceptance remains pending.

Implementation follow-up belongs to Core/evaluation and world implementation:
provide versioned exact-build rating evidence, validated comparability for bests,
active build/equipment identity, permanent Class assignment and milestone rules;
then render actual ratings and qualifications with their raw evidence context.
Completion requires replacement-build, stale-evidence and incompatible-history
cases, not merely populating the cards with numbers. No UI placeholder grants
qualification or authority.
