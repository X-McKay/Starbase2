# Live crew view

Status: proposed · implemented 2026-10-04 in the native client (agent transparency, slice 3)

The exploration HUD now consumes the [live event stream](operations.md#live-event-stream-v8)
so the operator can see what the SDLC crew is doing inside a long stage. The
stream reports *that* records changed. The `/v7/snapshot` and `/v2/snapshot`
polls stay authoritative: a stream record event only asks for a sooner `/v7`
refresh, and a `reset` refetches both snapshots. Activity notes are observations,
not evidence. No part of this view dispatches work or grants authority.

## Stream client

`apps/world/event_stream.gd` is a reusable node. Its signals are
`record_event(evt)`, `activity(evt)`, `reset(reason)` and
`connection_changed(state)`, where the state is `connecting`, `live`, `stale` or
`offline`.

- **Native:** Godot `HTTPClient` reads the chunked `text/event-stream` body. An
  incremental parser handles CR, LF and CRLF line endings, comments, multi-line
  `data:`, `id:` persistence, `retry:`, a BOM and lines split at any byte. A line
  over 1 MiB drops the connection.
- **Web:** `web_request.js` adds `StarbaseEventSource`, a same-origin browser
  `EventSource` with the existing origin check. The browser reconnects with
  `Last-Event-ID` on its own. When it gives up, the node reopens with
  `?after=<id>`.
- **Resume:** the last dispatched id is sent as `Last-Event-ID`. Heartbeats carry
  no id, so they never move the cursor.
- **Reconnect:** backoff starts at the server's `retry` (3 s), doubles and is
  capped at 30 s. A 404 from an older Core waits the full 30 s.
- **Liveness:** the stream is stale after a missed heartbeat window
  (`heartbeat_seconds × 2 + 1`, 11 s by default). After three missed heartbeats
  (16 s) the connection is dropped and reopened.
- **Fixture mode:** `--stream-fixture=<file.jsonl>` replays frames with relative
  timing. It never opens a connection. A header line names the paired synthetic
  V2 and V7 snapshots and a `reference_time`. The client shifts every timestamp
  so the last frame lands at replay time. Frames are either structured
  (`{"t","event","id","data"}`) or `raw` SSE text that goes through the same
  parser as network bytes. The fixture in `fixtures/world/transparency/` is
  synthetic.

## One freshness rule

`freshness.gd` drives the masthead badge, for example
`[~] LIVE · last event 0.8 s ago`. "Last event" means any frame, including a
heartbeat; a heartbeat is evidence of liveness, not of work. The states stay
distinct:

| State | Badge | Evidence |
|---|---|---|
| live | `[~] LIVE · last event N ago` | stream ready and within the heartbeat window |
| stale | `[?] STALE · last event N ago · heartbeat missed` | stream window missed |
| offline | `[/] STREAM OFFLINE · snapshot N ago` | stream down, snapshot poll fresh (≤ 5 s) |
| connecting | `[-] CONNECTING …` | first attempt, nothing live yet |
| disconnected | `[x] DISCONNECTED · last-known records only` | no fresh stream or snapshot |
| unknown | `[?] UNKNOWN · nothing received from Core` | nothing received |

A fixture replay appends `SYNTHETIC REPLAY`. An offline `--fixture` world with
no stream shows `[?] FIXTURE · no live stream or snapshot`. The colour is never
the only signal.

## Page 1 in the HUD

- **Live activity** (right column, toggled with **T**, listed in Controls) shows
  the last six events with UTC times. Examples: "Rivet ran tests · failed",
  "Prism requested changes · 2 findings" and "Core graded round 1 · improved
  (6/6 vs 4/6)". When a started note is followed by its finished note, the
  finished one replaces it. Finding and case counts come only from the retained
  `/v7` stage evidence, and only for the newest testing event. Below 1000 px the
  panel collapses to an `Activity · N [T]` tab, which **T** expands. It follows
  the larger-text setting.
- **Follow-card** sits above the watched crew member, or the one focused in the
  crew strip. It shows the name and role, the mission id, the revision round
  (`revision_count + 1`), the verb from the latest activity note (such as
  `[>] Running tests`) and the number of model requests and tokens observed in
  this session. A thin stem ties it to the actor's screen position. Verbs are
  current only while the stream is live, the note is under 120 s old and it
  belongs to the assigned mission. Otherwise the card says
  `[?] Activity unknown · stream not live` or `[-] No recent activity note`.
- **Crew strip** shows the same verb while it is fresh. The full status keeps the
  record label, and the strip falls back to the existing labels.
- **Reality Gate** (top right) shows the policy generation, the expiry
  countdown, missions used against the maximum (`≥` when the snapshot page is
  partial) and admission. It checks the policy (enabled and publish allowed),
  the test verdict and the reviewer status. Each check shows `[=]` passed,
  `[x]` failed or `[?]` missing; missing evidence is never shown as passed. The
  gate reads `LAST KNOWN` when the `/v7` snapshot is older than 15 s. It notes:
  "Opens only for: create branch and pull request. Never merges."

`capturing` and `reviewing` now count as working for crew motion as well as for
station signs. Station signals, briefings and crew presentation share
`state.gd` `WORKING_STATES` and `OPEN_STATES`.

## Verification

- `test_event_stream.gd` covers parsing, routing, resume, reset, staleness,
  backoff, freshness states and fixture replay. It also runs a loopback chunked
  HTTP server so the native `HTTPClient` path is exercised for real, including
  reconnecting with `Last-Event-ID`.
- `test_live_crew_view.gd` covers the activity, follow-card and gate text, and
  the HUD layout at 1440×900, 960×700 and 800×640 with normal and larger text.
- Native captures and their command are in
  [the evidence folder](../evidence/world/transparency-20261004/README.md).

## Limitations

- The Web `EventSource` path was not run in a browser here. Only the JavaScript
  bridge was checked, against a stand-in `EventSource` under Node, and that check
  was not committed. A Web export and browser run remain open.
- Activity notes carry only outcome classes. A failed `run_public_tests` note
  reads "ran tests · failed"; per-case detail appears only after Core retains
  testing evidence.
- Model request and token counts cover what this client observed since it
  connected. Notes are not replayed on resume.
- Verbs for crew members other than the SDLC lead, implementer and reviewer still
  come from record labels.
- Owner visual acceptance is pending. No frame-time measurement was taken; the
  captures used the llvmpipe software renderer.
