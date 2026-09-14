# Live-world UI evidence

This index covers the delivered first integration slice from approved steps 1–4,
not every original completion criterion. Native history pagination, distinct
spatial task/evidence markers and a separate worker-heartbeat timestamp remain
owned step-5 follow-ups. Current labels/counts and inspectors provide the initial
operational slice. This index does not claim
full native command parity, a complete return briefing, or Kubani activation.

## Integration suite status

`../world-check-01.log` preserves the full-suite failure caused by an interaction
fixture that omitted capability metadata while expecting repair submission.
Unknown capability correctly disabled the control. The revised fixture verifies
that case before supplying explicit enabled repair policy for the keyboard
action. `../interaction-focused-01.log` and `../commands-focused-01.log` pass;
the command fixture verifies six POSTs, GET reconciliation and no worker identity.
The full `just check-world` run in `../world-check-02.log` then passed with exit 0,
confirmed by independent QA. `../check-02.log` records the passing repository
suite. The subsequent final standalone `20260908-final-01` qualified with exit 0;
its [manifest](../package-01/manifest.json), logs and exported frames bind the
corrected final source rather than extending the earlier capture's claim.

## State and physical crew checks

`live-world-state-before.log` preserves the failing active-history regression.
`live-world-state-after.log` passes active/recent deduplication, evaluation-to-
Trainer context, metadata retention, malformed nested input and stale/evidence
semantics. Backend request kinds remain unchanged.

`live-world-crew-presentation.log` passes stable concurrent assignment,
out-of-order snapshots, reconnect coalescing, reduced motion, outage and missing
evidence behavior. Presentation owns no dispatch or durable work state.

`live-world-engineering.log` preserves the first arrival failure. Diagnosis in
`live-world-engineering-diagnosis.log` found the half-metre navigation endpoint
left Mender 0.3449 m from a workstation with a 0.3 m pose gate. The movement
adapter now appends the authored point only after existing segment-clearance
validation. `live-world-engineering-after.log` passes, including an idle inspector
that does not trigger work, execution/arrival pose and cancellation-pending stop.

`live-world-five-crew-first.log` and `live-world-five-crew-diagnosis.log` preserve
the two exterior Command crew blocked by the operator-only Airlock. The corrected
station also considers nearby NPCs for door opening, while keeping cutaway based
on the operator. `live-world-five-crew-after-airlock.log` passes five physical
routes, continuous 1.3 m/s bounded travel, arrival/pose, reduced motion, outage
and no dispatch. Watchkeeper traveled 25.13 m and Reviewer 17.94 m; all five
stopped approximately 0.10–0.12 m from their authored workstation. NPC entry did
not change the operator camera, room context, position or Command cutaway.

Reproduce focused tests from the repository root after normal import:

```sh
godot --headless --path apps/world --script test_state.gd
godot --headless --path apps/world --script test_crew_presentation.gd
godot --headless --path apps/world --fixed-fps 60 --script test_engineering_polish.gd
godot --headless --path apps/world --fixed-fps 60 --script test_live_crew.gd
```

The physical crew tests inject explicit offline records and start with fixture
mode before scene initialization. They are actual collision/animation tests,
not evidence that five real backend jobs executed.

## Live native attempts

- `native-01` produced no capture. Retain it as an unsuccessful attempt.
- `native-02` produced only the colony PNG and did not complete. Read-only process
  sampling found the main thread mostly sleeping rather than a busy UI loop.
  Coroutine/object lifetime was investigated, but the precise cause was not
  independently proven. Do not describe this as a conclusively diagnosed engine bug.
- `native-03` completed eight live captures with an empty failures list and
  `commands_dispatched: false`: colony, connection, Command, repositories,
  evidence, compact connection, client-disconnected and reconnected views.
  The Core reported development policy, field work enabled, memory/inference/
  repair disabled. It retained one completed observation and a distinct cancelled
  run. This attempt preceded the subsequent button-layout correction.

The complementary `../real-03/` backend rehearsal observed only the approved
private repository through GET-only adapters. It exercised a worker restart,
duplicate identities, queued cancellation before capture, durable duty pause and
retained detail across Core restart with Godot closed. Completed source time is
recorded; the uncaptured cancellation has null source time. Unsupported-language
coverage remains explicit. No model call, GitHub publication or cluster deployment
was part of this evidence.

Standalone qualification against frozen final sources passed in
`20260908-final-01`; root reverified all world sources, runner, archive, executable
and PCK hashes against `../package-01/manifest.json`. Root and independent review
inspected the final live UI. Eight exported live captures include client-read
outage/reconnect and no commands dispatched, not a real provider outage. The
local archive is `.local/reviews/live-world/20260908-final-01/Starbase2-macOS.zip`.
The earlier native frames still do not qualify later edits. Full native parity/return briefing belongs to step 5;
authorized target deployment and overnight recovery qualification belong to
step 6. Owner art acceptance and human audio audition remain open.
