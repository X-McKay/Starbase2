# Native interface polish

Status: accepted

Date: 2026-09-07. Scope: the Godot client's HUD, crew inspector, station
directory, field guide, and command board. No backend, contract, deployment or
authority change. Records, projections and command semantics are unchanged.

## Why

The first playable passes assembled the interface from per-panel styles: plain
default tabs, text-only status, colour-only state, a command board that bled the
scene through its background, and a bottom bar whose crew roster was one long
sentence. Reviewing the retained captures
([inspector](../evidence/building-catalog/stale-compact.png),
[command board](../evidence/command-district/findings-compact-final.png)) showed the
world had outgrown its chrome. This pass gives every panel one visual system and
makes state legible without colour.

## Implemented

One theme module, [`ui_theme.gd`](../apps/world/ui_theme.gd), owns colour tokens,
a type scale, panel/button/input/tab/scrollbar styles and small composable parts.
The palette follows the shadcn dark convention: near-black zinc surfaces, one-pixel
neutral borders, white headings, muted secondary text and a single orange accent
for primary actions, key caps, section titles and prompts. Button variants are
secondary (default), primary, outline, ghost, destructive and icon; tabs are a
segmented list. The parts are:
section rules, cards, key caps, badges, chips, toasts and a `Glyph` control. Every
panel is built from those parts; no panel defines its own colours.

- **Shape-coded status.** A tone (`live`, `verified`, `pending`, `stale`,
  `unknown`/`offline`, `failed`, `idle`, `no_change`, `fixture`, `paused`) maps
  to a drawn shape *and* a colour, and the state word stays in the label. Filled
  disc, check, ring-with-dot, half disc, ring, cross, dash, equals, diamond and
  pause bars remain distinct with colour removed. The projection in
  [`state.gd`](../apps/world/state.gd) (`tone`, `crew_tone`) derives the tone from
  the same record fields as the text; it adds no information the record lacks.
- **Masthead and navigation.** Eyebrow, title and a connection pill whose glyph
  follows live/stale/offline/unknown/fixture. Map, Crew and Journal carry key caps.
- **Bottom bar.** A structured prompt (key caps plus text) replaces free text,
  the key legend is a row of caps, and the roster is one chip per crew member
  with its tone and activity. Compact viewports move the legend to its own
  wrapping row.
- **Inspector dock.** Loadout card with portrait, a two-button action grid,
  a retained-records selector that disables itself when empty, a state card with
  badge, detail and collapsible evidence, a progression badge, the isolated
  practice form with a primary launch button, a danger-styled cancellation
  button, and a feedback strip that only appears when a command reported
  something. Long captions trim rather than widen the dock.
- **Directory and field guide.** Crew entries show the same roster tone and
  activity beneath their key-capped buttons; places remain searchable. The
  guide lists keys in a cap/description grid with the comfort toggles beneath.
- **Command board.** Header with eyebrow, connection pill and Escape-capped
  close; a notice strip that carries the last command outcome tone; styled tabs;
  one card per observation, watched repository, PR duty and memory proposal
  with a state badge and an action row; empty states as inset strips; an
  evidence page with a header card, one card per finding with a code chip,
  coverage limits as stale badges and the raw record behind a toggle.
- **Modal behaviour.** Directory, guide and board open above a scrim that
  absorbs clicks and closes on click; the dock stays a side panel so the world
  remains visible. Panels fade in over 160 ms, or appear immediately under
  reduced motion. Transient notices (command outcome, verified achievement) show
  as a toast for a few seconds; the authoritative text remains in the dock.
- **Larger text.** The whole theme is rebuilt one step larger instead of
  patching individual labels; the board follows.

## State ownership

| Presentation | Source | Distinguishable states |
|---|---|---|
| Connection pill | HTTP outcome, snapshot schema, five-second freshness bound, fixture flag | live, stale, offline, unknown, fixture |
| Inspector state badge | `StateView.describe` and `StateView.tone` of the selected retained record | idle, pending, stale, unknown, failed, verified, no change, offline |
| Roster chips and directory rows | `StateView.crew_activity` and `StateView.crew_tone` per crew kind | as above, plus concurrent-run counts in the text |
| Board record badges | v4 run/watch/memory state fields; watch staleness from interval and timestamp | pending, completed, failed, cancelled, enabled, paused, removed, stale |
| Toasts and notice strip | Command feedback and the progression ledger | accepted, rejected, uncertain outcome, pending, verified |

Scenery, portraits, poses and the fade animation carry no state. Fixture runs
label themselves and keep every mutation disabled, as before.

## Verification

- `just check-world` now includes [`test_ui.gd`](../apps/world/test_ui.gd):
  distinct tone shapes, key caps, roster chips, structured prompts, dock,
  directory, guide and board bounds at 1280×800 and 960×720 with larger text,
  scrim and focus handling, toast and reduced-motion reveal. Existing state,
  command-board, interaction, room, field-crew and building checks still pass;
  the state test gained tone cases.
- Actual renders under a virtual display are retained in
  [evidence/world-ui](../evidence/world-ui/README.md): normal, inspector,
  compact larger-text inspector, compact directory, guide, board evidence and
  repositories pages, disconnected core, and reduced motion, with the baseline
  captures for comparison. The capture JSON frame intervals come from a software
  renderer and are not a performance measurement.

Preserved failures from this pass: the first reveal animation wrote a stale
hidden-panel size into the anchored offsets (fixed by fading only), buttons
with trimmed overrun lost their captions from their minimum size (fixed by
trimming only inside fixed-width rows), and the first UI test asserted on an
un-rendered board (fixed and strengthened).

## Limits and next gate

Headless layout checks are not a screen-reader or contrast audit; the browser
journal remains the structured accessibility path. The default engine font is
unchanged. Gamepad navigation, persisted comfort settings and a full colour
contrast measurement remain open with the earlier comfort gate in
[world-playable](world-playable.md). Owner: Al reviewing in-game at intended
zoom; the next interface gate is that review, then a matching pass over the
browser journal so both clients share one status vocabulary.
