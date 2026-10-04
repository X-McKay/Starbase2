# Workstation screen

Status: proposed · implemented 2026-10-04 in the native client (agent transparency, slice 4, page 2)

The workstation screen is one crew member's console, opened from the world. It
answers "what is this crew member working on, and what did it actually do?"
using only retained records and stream observations. It never dispatches work,
changes a mission or grants authority. The [handoff dialogue](handoff-dialogue.md)
(page 3) shares its data path.

## Opening it

| Way in | Result |
|---|---|
| **N** | Toggles the console. It opens for the watched crew member, or the one focused in the crew strip. With neither, it opens for whoever the latest mission's state assigns (lead while investigating, implementer while implementing, reviewer while testing), else Rivet. |
| Crew strip **Console [N]** | The same, by mouse or keyboard focus. |
| **← / →** or the **← Crew / Crew →** buttons | Step between Moss (lead), Rivet (implementer) and Prism (reviewer). |
| **PageUp / PageDown** | Scroll the console. Below 1200 px the panes stack into one scrolling column. |
| **Handoff [U]** | Switch to the handoff dialogue for the same mission. |
| **Esc** or **Back to room [Esc]** | Close. Esc also stops watching, as elsewhere. |

The console is a HUD workspace: while it is open the player does not walk, and the
crew strip and live overlays are hidden. The Controls help lists **N** and **U**.

## What it shows and where each value comes from

| Pane | Source | Distinct states |
|---|---|---|
| Header | Crew name and role; mission id, repository, round `revision_count + 1` of `coordination.max_rounds`, state from the `/v7` summary; masthead freshness text from `freshness.gd` | `SYNTHETIC` in fixture replay |
| Banner | Freshness, full-record read status, mission state | `[?] LAST KNOWN` (stream not live or `/v7` snapshot older than 15 s), `[=]` record read N ago, `[-]` loading, `[x]` read failed, `[?]` record not available, `[\|\|]` blocked/stopped, `[x]` failed |
| Plan | Lead `task` and `rationale` from `stage_evidence.plan` (or the `lead-handoff` event); steps from the retained `coordination.assignments` plus publish and human review | `[=]` done, `[>]` current step, `[ ]` ahead, `[\|\|]` stopped, `[?]` unknown step or "recorded; Core decides next" |
| Reviewer asked for | Findings, status and `missing_evidence` of the latest review at or before this round (`review-N` events); summary `stage_evidence.reviewing` without the full record | `[!]` changes requested, `[=]` accepted, `[?]` abstained or not reported, `[x]` patch rejected before execution, `[-]` no review yet |
| Why this step | Nothing: model reasoning is not stored | Always `[?] Not recorded`, citing [ADR 0015](adr/0015-agent-reasoning-trace-evidence.md) (proposed) |
| Live diff | The unified `diff` of the latest `testing-N` event, rendered line by line with `+`/`-` kept in the text | `[-]` no source change (empty diff), `[?]` diff not recorded, stats only from the summary when the full record is missing, "round N (last retained; round N+1 not submitted)" when the current round has no candidate yet, `[x]` rejected before execution |
| Test rig | Core-graded `baseline_cases` / `candidate_cases` and `verdict` from the `/v7` summary (current round only) | `=` / `x` cells plus text; `[?]` not executed; `[-]` not graded yet; expected values stay with Core's oracle |
| Spend | Recorded `usage`, `model_requests`, `usage_complete` and `elapsed_ms` of the role's member result; tokens and requests observed from stream notes this session | Unknown stays unknown (never zero); `[?]` usage incomplete; cost is always "not recorded" |
| Tool receipts | The role's retained receipts (`tools[]`): tool, `ok`, `elapsed_seconds`, `cached` | `[=]` ok, `[x]` failed, `[?]` outcome not recorded; a fresh `tool_started` note appears as `[>] running · stream note, not a receipt` only while the stream is live |

Receipts keep an input digest, not the arguments, so the console says
"Arguments not recorded". Error text in a receipt is not shown, because it can
quote source; the outcome class is.

When the current round has no recorded result for the selected role (for example
Prism while reviewing round 2), the spend and receipt panes fall back to the
latest recorded round and say which round they show.

## Data path

- `mission_story.gd` reads one full record from `GET /v7/missions/{id}` as rounds:
  a `reviewing` → `implementing` transition starts the next round, as in Core.
  Event data is the worker-submitted data; Core's verdict and grading live only in
  `evidence.testing` and the summary, for the current round.
- `mission_record.gd` fetches that record when the mission's summary changes
  (`updated_at`, `event_count`, `state`). A stream record event already asks for a
  sooner `/v7` poll, so a new stage reaches the console within one refresh. A failed
  read keeps the last known record, reports it, and retries after 10 s.
- `transparency_pages.gd` builds both pages' models every 0.2 s while one is open,
  from the world's summary, record, activity notes and freshness. Panes are rebuilt
  only when their content changes.
- In fixture mode (`--stream-fixture=`), the stream header's `v7_missions` names the
  synthetic full record; no request is made.

## Verification

- `apps/world/test_transparency_pages.gd` (registered in `scripts/check_world.py`)
  covers the models (recorded, stale, failed read, missing record, loading, round
  not graded, previous-round diff, no-change diff, blocked, failed, patch rejected,
  no role, no mission, in-flight note), the HUD layout at 1440×900 and 960×700 with
  normal and larger text, and a keyboard journey through the world with the
  synthetic round-2 fixture (N, ←, Esc, U, U, stale).
- Native captures are in
  [the evidence folder](../evidence/world/transparency-20261004/README.md).

## Limitations

- Model reasoning and tool arguments are not recorded. Slice 7 may add them behind
  ADR 0015, which is proposed, not accepted.
- Per-case grading exists only for the current round. Earlier rounds show their
  diff and receipts but not their case outcomes.
- The console does not mark which reviewer finding a revision addressed; that is
  the next review's judgement.
- The Web build was not exercised. The full-record read uses the same transport
  as the SDLC missions tab.
- No frame-time measurement was taken. Captures used the llvmpipe software renderer.
- Owner visual acceptance is pending.
