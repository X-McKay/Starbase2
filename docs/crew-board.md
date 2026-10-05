# Crew board and crew dialogue

Status: proposed · implemented 2026-10-04 in the native client (agent transparency, slice 6)

The crew board (page 5, design 5E-R3) and the crew dialogue (page 6, design 5B)
answer three questions in one place: what happened, what needs the operator, and
where everyone is. They build on the [live crew view](live-crew-view.md) and use
the same freshness rule. Both are projections. They dispatch no work, grant no
authority and never show model-generated text.

## Sources

Every line comes from an authoritative record:

- the polled `/v7/snapshot` (policy, coordination, mission summaries and their
  `recent_events`, publication), see the [V7 contract](../contracts/sdlc.schema.json);
- the polled `/v2/snapshot` (repair, review and field-agent records);
- the [`/v8/events` stream](operations.md#live-event-stream-v8) (record events and
  transient activity notes, through `live_activity.gd`).

The memory review queue lives in `/v4`, which this board does not read. The board
says so ("Memory notes · not in these records") instead of showing a count that
could be wrong. Scheduled duties are also `/v4` and are not shown.

## Page 5 · Crew board

Open it with **Tab** or the **Crew** navigation button. Focus lands on the first
crew row, so **Tab** and **Shift+Tab** then move through the board's controls.
Tab still traverses focus; it only opens the board when no control has focus.
The old *Crew & places* directory moved to **P** (also a button in the board's
header). **Esc** closes the board.

Left side:

- **Needs you**, oldest first, with one action each:
  - *Review PR #N on repo* for a mission in `awaiting_review`/`submitted` with a
    recorded PR. **Open PR** opens the recorded link only when it passes the same
    `github.com/<repository>/pull/<n>` check as the SDLC missions tab; otherwise it
    says no safe link is recorded. Crew never merge.
  - *Mission N blocked/failed* in the last 24 h. **Inspect** opens that mission in
    Field ops → SDLC missions.
  - *Publish policy ends in 2d 14h* when the policy expires within three days, or
    *expired* (`[x]`). **Extend** is not available here: it says that an operator
    renews the policy with a new generation through `POST /v7/policy`.
  - *Memory notes · not in these records* (`[?]`, counted as unknown). **Review in
    Field ops** opens the existing Memory page.
- **Alert chips**: `[x] Next mission blocked: <admission>` when Core's admission is
  not `ready`, `[?] Admission unknown` without a V7 snapshot, `[/] <name> silent N m`
  or `[/] <name> stale · worker unavailable` per crew member, and
  `[x] Core disconnected · last known`. A chip opens the dialogue on the matching
  question.
- **Activity**, newest first (14 rows): stream records and notes, retained
  `recent_events` not already seen on the stream, mission admission and PR
  publication, and `/v2` record updates. Each row shows UTC time, who (crew member
  or Core), a glyph and the text; the tooltip names the source.

Right side:

- **Crew**, one line each: Moss (lead, duty officer), Rivet, Prism, Wes, Mae, with
  one status marker, state and what they are doing. A legend under the list
  explains the markers, and each tooltip names its marker's meaning. **Enter** selects or clears a member;
  selecting filters the feed to that member (**Show all crew ×** clears it).
- **Their day**: role, state and place, runs in the last 24 h, tokens, *Doing now*,
  *Up next*, *Done · last 24 h*, and **Talk [T]** and **Watch in the world [W]**.
  With nobody selected the panel shows Moss as duty officer.

### Member states

| State | Glyph | Rule |
|---|---|---|
| working | `[>]` | open `/v2` record, or the V7 stage is assigned to this role; the verb comes from a fresh activity note only while the stream is live |
| waiting | `[_]` | on the active V7 mission, another role holds the stage |
| queued | `[...]` | only queued `/v2` records |
| idle | `[-]` | no open record and no active mission |
| silent | `[/]` | an open `/v2` record has not changed for 5 min or more (relative to the snapshot's `observed_at`) · last known |
| stale | `[/]` | Core marks the open record stale (worker unavailable) · last known |
| unknown | `[?]` | no current `/v7` for an SDLC role, or `/v2` disconnected · last known |

"Silent" is an observation that a record stopped changing, never a claim that the
work failed. *Up next* for the SDLC trio follows the V7 stage order (for example
"Hand round 2 to Core for testing"); for other crew it is the next queued record or
"Nothing queued in the records". Tokens are only those observed on the stream in
this session; other crew show "tokens not recorded". "Last 24 h" is used rather
than "today" so the result does not depend on the UTC day boundary.

## Page 6 · Crew dialogue

**T** (or **Talk**) on the board opens the dialogue with the selected member, or
with Moss when nobody is selected. **1–5** ask:

1. What is waiting on me?
2. Why can't we start another mission?
3. Is everyone accounted for?
4. What finished in the last 24 h?
5. Carry on (closes)

Answers are fixed templates in `crew_dialogue.gd` filled only from the board model.
Each answer ends with a **Based on:** line naming the records it used, for
example `Based on: admission active_mission · mission sdlc-42 state implementing ·
/v7 snapshot 1 s ago`. When the `/v7` snapshot is not current the answer starts
"As of the last snapshot:". When a record is missing the answer says it does not
know.

A crew member whose state is silent, stale or unknown does not speak. Moss answers
for them ("answering for Wes (silent 6 m · last known) from last known records")
and the board's button reads **Ask Moss about Wes [T]**. If Moss is also last
known, the "Station record" answers without a persona. **Esc** closes the dialogue
and returns focus to **Talk**; a second **Esc** closes the board. While the
dialogue is open the board behind it is dimmed.

## Keys

| Key | Where | Action |
|---|---|---|
| Tab | world | open the crew board (inside the board, Tab moves focus) |
| P | world | Crew & places directory (was Tab) |
| Enter / Space | board | activate the focused control; on a crew row, select or clear |
| T | board | open the dialogue (outside the board T still toggles Live activity) |
| W | board | watch the selected member (acts on key release, so the held key does not walk) |
| 1–5 | dialogue | ask a question (does not open a dossier) |
| Esc | dialogue / board | close the dialogue, then the board |
| J / R | world | Work & history; R was bound but missing from Controls help |

`test_key_help.gd` parses the world's key bindings and fails when a bound key is
missing from Settings → Controls or a listed letter is not bound.

## Comfort settings persist

Reduced motion, larger interface text, ambient sounds and the crew summary toggle
are saved in `user://starbase2-player.cfg` (section `comfort`) beside the character
choice, and restored at start. `--large-text` and `--reduced-motion` still force
those settings on. Malformed values are ignored. Fixture runs, and any harness
that instantiates the world with the default path, neither read nor write personal
preferences, so a saved setting cannot change a test run.

## Fixtures and verification

- `fixtures/world/transparency/crew-board-stream.jsonl` replays the slice 3 stream
  frames paired with `crew-board-v7.json` (adds mission 41, accepted, PR #118) and
  `crew-board-world.json` (an invented repository review, repair trial and three
  watchkeeper records, one of which stopped changing six minutes before the
  snapshot). All synthetic and labelled; the slice 3 fixtures are unchanged.
- `test_crew_board.gd`: projection, distinct states, needs and actions, feed order
  and filter, every templated answer and its sources, Moss answering for a stale
  member, keyboard Tab/Shift+Tab/Enter/T/W/1–5/Esc, and layout at 1440×900 and
  960×700 with normal and larger text.
- `test_key_help.gd`: reproduces the R help defect (it fails on the slice 3 HUD).
- `test_comfort_settings.gd`: settings survive a restart and are applied.
- Native captures: [evidence](../evidence/world/transparency-20261004/README.md).

## Limitations

- Memory notes and scheduled duties need `/v4`; the board marks them unknown and
  links to Field ops instead.
- *Up next* for the SDLC roles is the stage order applied to the recorded state,
  not a schedule.
- Token counts cover only what this client observed on the stream.
- "Silent" uses a fixed 5-minute threshold on record updates; a long, healthy
  step without record updates will read as silent (last known), never as failed.
- Owner visual acceptance is pending; captures used the llvmpipe software renderer.
