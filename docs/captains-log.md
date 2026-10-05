# Captain's Log

Status: proposed · implemented 2026-10-04 in the native client (agent transparency, slice 5)

The Captain's Log is page 4 of the agent transparency work. It shows one SDLC
mission as a timeline, with one horizontal lane per crew role (Moss as lead, Rivet
as implementer, Prism as reviewer) and a lane for Core. Each event sits at the time
it was recorded. Selecting an event opens a detail panel with that event's evidence
from the record. The log is read-only and dispatches nothing.

Press **G** in the world to open it. **G** or **Esc** closes it. The key is listed
in Controls under *Mission records*. G was free. R was avoided because a separate
change is resolving a help clash on R. The log opens on the mission the
[Reality Gate](live-crew-view.md#page-1-in-the-hud) shows: the followed crew
member's mission, otherwise the selected SDLC mission, otherwise the most recently
updated one. It stays on that mission until it is closed.

## Sources

Every event comes from an authoritative record. Nothing is inferred beyond what
those records hold.

| Source | Used for |
|---|---|
| `GET /v7/missions/{id}` (the full record) | `events[]` entries (key, stage, data, Core receipt time `at`), `created_at`, the `publication` claim and its `effects`, and `pr_observation` |
| `GET /v7/snapshot` (the summary) | which mission to show, `assigned_crew`, current-round case counts from `stage_evidence.testing`, the current `coordination.admission`, and `recent_events` as a bounded fallback |
| `/v8` stream frames already received | `mission.stage` frames whose key the fetched record does not hold yet (provisional), `mission.publication` before the record shows a claim, `mission.cancel_requested`, and transient tool and sandbox activity notes |

The full record is reread when the summary's `updated_at`, `event_count`, `state`
or `publication` changes. Stream record events already trigger a sooner `/v7`
refresh (see [live crew view](live-crew-view.md)), so a new stage appears first as
a provisional `~` pin and then as a record once the reread lands. Only one request
is in flight at a time.

## Events

| Record | Lane | Shown as |
|---|---|---|
| `created_at` | Core | Mission admitted: repository, opportunity, pinned revision, policy generation, retry parent |
| `investigating` | Core | Sources captured · N files: source digest, baseline run, scope. The capture has no crew role, so it sits on the Core lane. |
| `implementing` from the lead | lead | Plan handed to the implementer: decision, task, stated rationale, model usage |
| `implementing` from the reviewer (`revise-N`) | reviewer | Sent back for revision |
| `implementing` or `reviewing` from `patch-validator` | Core | Patch returned or validator revise: nothing ran |
| `testing` | implementer and Core | One record becomes two events at the same time: the patch (diff stats, candidate run, artifact digest, stated rationale, usage) and Core's grade (verdict, baseline and candidate pass). Case counts appear only for the current round, because the summary keeps only that round. |
| `reviewing` | reviewer | Accepted, changes requested, abstained or status not recorded: findings with path, line, problem and evidence, plus missing evidence |
| `ready_to_publish` | Core | Gates passed |
| `publication.claimed_at` | Core | Publication authority claimed: branch, authority text and effect claims |
| `publishing` receipts | Core | Branch pushed, PR opened #N, review comment posted |
| `submitted` | Core | PR #N submitted (not a merge, a production verification or an XP award) |
| `awaiting_review` | Core | Awaiting human review: CI status, verified merge, XP |
| `pr_observation.observed_at` | Core | PR observed · open, closed or merged (read-only) |
| `blocked`, `failed`, `cancelled` | role's lane, else Core | Lead abstained, implementer abstained, model request failed, review blocked or the bounded activity ended, with the recorded reason |

Admission refusals have no timestamped mission record. When an activity refuses
or blocks a mission, the refusal is recorded as a `blocked` stage and appears on the
timeline. When Core denies a gate it returns an HTTP error and keeps nothing. The
current `coordination.admission` (for example `active mission` or `policy budget`)
is shown in the header and labelled *current Core state, not a timeline event*.

Core keeps the returned model output, usage and elapsed time. It does not keep the
model's reasoning or tool arguments. The detail panel lists these as *not recorded*
under **Not recorded**. Cost is not recorded either. Token totals come from the
`usage` retained in member results. A result with no usage counts as a request with
unknown usage, never as zero tokens, and the total is shown as a lower bound (`≥`).

## Distinct states

The header shows the masthead freshness line from `freshness.gd` (live, stale,
offline, connecting, disconnected or unknown) and a record line:

| Record line | Meaning |
|---|---|
| `[=] Full record · read N ago · K retained events` | full record read and the `/v7` snapshot is current |
| `[?] LAST KNOWN · /v7 snapshot older than 15 s` | full record held, snapshot stale |
| `[x] Record read failed · showing last known record` (or `· showing the bounded summary`) | the last reread failed |
| `[-] Reading full record · showing the bounded summary` | first read in flight; only `recent_events` are placed |
| `[?] Summary reports N events; record holds K · rereading` | the record is behind its summary |
| `[?] UNKNOWN · no /v7 snapshot received` | nothing received |
| `[-] No V7 mission recorded · nothing to show` | snapshot received, no mission |
| `[=] Synthetic fixture record · K retained events` | fixture replay |

Pins are marked by kind as well as by colour:

- **Filled numbered pins** are retained records.
- **Hollow pins** are live stream observations. Core does not retain them and they
  are not replayed after a reconnect.
- **`~` pins** were announced on the stream and are waiting for the record.

A patch with an empty diff reads `[-] … no change`. A rejected patch reads
`[x] … rejected · not executed`. A missing verdict reads `[?] … not recorded`.

## Layout and interaction

- **Header.** Mission title, then repository, admission time, current state and
  round, retained tokens and "cost not recorded". The actions are Previous `[,]`,
  Next `[.]`, List view `[L]` and Close `[Esc]`.
- **Timeline.** A tick row in UTC, a *Mission state* band derived from consecutive
  stage records, four lanes, a white cursor at the selected event and a dashed
  *now* line for an active mission. A quiet gap is collapsed when it is longer than
  4 minutes and longer than four times the median gap between events. A collapsed
  gap is drawn as a narrow shaded break labelled, for example, `≈ 3 h quiet`. Pins
  close together in one lane are spread so each stays clickable.
- **Detail panel.** Event N of M, UTC time, title with its glyph, crew, role, stage
  and kind, body, **Evidence from the record**, **Not recorded** and **Source**
  (for example `/v7/missions/sdlc-42 · events[2] · key testing-1`).
- **Tokens per crew.** Retained tokens and requests per lane. Below 1100 px the
  rows fold into the lane labels (`implementer · 8.7k tok`) and the detail column
  narrows to 300 px.
- **Keyboard.** `,` `.` or Left and Right step in time. Up and Down move to the
  nearest event in the adjacent lane. Home and End jump to the first and last
  event. Tab and Shift+Tab move between pins in time order, and focusing a pin
  selects it. Click selects too.
- **Chronological list.** **L** switches to the structured non-spatial equivalent.
  It has one row per event with its number, UTC time, crew, glyph, title and kind,
  and shares the same selection and detail panel. Up and Down move between rows.

## Code

- `apps/world/captains_log_model.gd`: pure projection (events, lanes, axis with
  collapsed gaps, ticks, state bands, status lines, tokens, lane neighbours, list
  lines).
- `apps/world/captains_log.gd`: the HUD workspace (rendering, selection, keyboard,
  the full-record fetch and fixture records).
- Small additive hooks: `hud.gd` (instance, `open_captains_log`, `is_open`,
  `close_panels`, workspace label, Controls) and `world.gd` (**G**,
  `toggle_captains_log` and `update_captains_log` from the existing 0.2 s
  live-view refresh).
- Fixtures: `fixtures/world/transparency/mission-sdlc-42.json` is the full record
  paired with `v7-snapshot.json`, named in the `stream.jsonl` header as
  `v7_missions`. `mission-sdlc-40.json` is a test-only published mission with a
  rejected patch, two rounds and a 3-hour CI wait. Both are synthetic.

## Verification

- `test_captains_log.gd` (registered in `scripts/check_world.py`) covers:
  - fixture consistency with the summary;
  - the exact mission 42 timeline, lanes, tokens, evidence and *not recorded*
    lines;
  - every record state, the summary fallback and provisional stream stages;
  - the mission 40 PR path and the collapsed 3-hour gap;
  - unknown usage, no change, refusals and blocks;
  - axis placement;
  - keyboard, click and Tab selection;
  - the list equivalent;
  - layout at 1440×900 and 960×700 with normal and larger text, and closing.
- Writing the test exposed a defect: pins near the end of a crowded lane were
  pushed outside the timeline. The pin-placement assertion failed first, and the
  fix spreads pins back inside the edge.
- Native captures and their command are in
  [the evidence folder](../evidence/world/transparency-20261004/README.md).

## Limitations

- Verification child records (`verifications[]` on the full record) are not placed
  on the timeline yet.
- A failed reread is retried only when the summary changes again.
- Admission refusals that Core returns as HTTP errors are not retained anywhere,
  so they cannot appear.
- Activity notes are only those this client received since it connected (at most
  the last 50 live activity entries). They disappear after a restart.
- The *Replay in world* action in the mock-up is not implemented.
- The Web build was not run. Owner visual acceptance is pending. The captures used
  the llvmpipe software renderer, and no frame-time measurement was taken.
