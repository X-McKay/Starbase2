# Live world / autonomous repository acceptance

The repository check passed in `check-02.log`. The full world suite first failed
in `world-check-01.log`: an older interaction fixture omitted installation
capability metadata but still expected the repair command to be enabled. The
client correctly treated unknown capability as disabled. The corrected fixture
first verifies that unknown capabilities disable submission, then explicitly
enables repair policy for its keyboard-command check. This is a test-precondition
correction, not relaxation of runtime admission. `interaction-focused-01.log`
and `commands-focused-01.log` pass; the latter verifies six fixture POSTs and
GET-only reconciliation without worker identity. The complete subsequent
`just check-world` run in `world-check-02.log` passed with exit 0, confirmed by
the independent QA task. Earlier failures remain retained.

Final standalone `20260908-final-01` qualified with exit 0. The
[durable manifest](package-01/manifest.json), logs, actual exported PNGs and JSON
are retained under `package-01/`. Root reverified every world source, runner,
archive, executable and PCK hash against that manifest; root and independent
review inspected the corrected final live UI. The local archive is
`.local/reviews/live-world/20260908-final-01/Starbase2-macOS.zip`, with its playable
app extracted for review. Eight live captures exercised retained evidence and
client-read outage/reconnect without dispatching commands. This did not induce
an actual provider outage and is not Kubani activation or owner art acceptance.

The reusable `scripts/live_world_integration.py` launches an owned Core and persistent Temporal development server on loopback ports 18801/17251, plus the application worker. It binds the existing GitHub identity to the single user-approved private repository `X-McKay/Starbase2` through the existing GET-only adapter. Identity scope is not claimed to be narrow. The credential is copied directly to a private 0600 file, never printed, and deleted with the runtime token during cleanup. Memory, inference, repairs and legacy execution are disabled. No GitHub writes, model requests, or deployment occur.

The harness starts the repository duty without launching Godot, restarts its worker while the timer sleeps, awaits one retained real observation, verifies exact/changed duplicate behavior, cancels a queued run before dispatch, pauses the actual Temporal duty, and restarts Core while checking the original detail is unchanged. It then leaves the owned backend available for native/exported review for a bounded hour. The duty stays paused, so review does not trigger further provider reads. `processes.json` and private databases/logs remain under the named ignored `.local` directory. Creating its `STOP` file or SIGTERM to the harness initiates owned-process cleanup and credential removal.

`real-01` passed the real observation/restart/pause/duplicate acceptance and was cleaned up. The observed PR had zero configured Python-rule findings and explicit unsupported-language coverage; this is not a repository quality or security certification. The harness launched no Godot client; the observation completed without a client connected to this isolated backend.

`real-02` retained the initially misplaced cancellation check: a new run was submitted after repository pause and Core correctly rejected it with HTTP 409. Owned processes and credentials were removed. This was a test-precondition error; the final harness queues and cancels while the repository is enabled, then pauses.

`field-focused.log` records 9 passing credential-free adapter tests: revision drift, GET-only behavior, repository budget, scoped credential binding, changed-line handling and disabled-work fencing. Ruff and ty pass for the new harness. Existing simulated failure fixtures remain complementary to the real-provider run; their outcomes must not be described as live-provider outages.

The native qualification procedure is to connect the application to the ready Core endpoint, show installation/capability reasons and the repository's paused duty, inspect the retained completed observation and source observation timestamp, and verify the cancelled run stays distinct. Capture Command overview/detail, room interaction and narrow-window layout with actual world processing. Then close the client, verify retained Core state, and repeat in the exported application with exact artifact/source hashes. The captured report's coverage limits must remain visible; zero findings must not imply a clean bill of health. These are qualification steps, not a statement that each final artifact has passed. The UI evidence index records native-03 results and their pre-layout-correction scope. The later final standalone qualification passed as recorded above; preserve native-03 as evidence of its own pre-correction source.

`real-03` passed the corrected complete acceptance: real observation, worker restart during duty timer, exact duplicate identity, changed duplicate rejected with HTTP 409, queued cancellation with no snapshot/report, actual Temporal duty pause, and identical retained detail after Core restart. The updated compact summary has a source observation timestamp for completed work and null for the uncaptured cancelled run (`summary-verification.json`). Its bounded review endpoint was `http://127.0.0.1:18801`, with private state under `.local/live-world-review-03`. The recorded ready time plus its 3600-second hold gives an expected automatic cleanup at approximately 2026-09-09 03:08 UTC; this document does not assert the endpoint remains active. Create `.local/live-world-review-03/STOP` when review finishes; verify the final cleanup event and token absence. Do not infer production readiness from this loopback development stack.


To reproduce a newly authorized run against the same approved repository, choose
fresh output/evidence directories and run from the repository root:

```sh
.venv/bin/python scripts/live_world_integration.py --output .local/live-world-review-new --evidence evidence/live-world/real-new --hold-seconds 3600 --gh-credential
```

This uses the existing GitHub identity and performs real bounded reads; it is not
an offline fixture command. Keep `--gh-credential` limited to expressly authorized
identity reuse. Do not overwrite retained attempt directories. To stop the owned
review early, create its output directory's `STOP` file or send SIGTERM to that
harness process. After automatic or requested shutdown, verify the
`owned_processes_stopped_credentials_removed` event and the absence of the two
private credential files. A deadline alone is not evidence cleanup completed.

Repository validation passed in `check-02.log` after a formatter-only correction to the export runner; initial formatter failure retained in `check-01.log`. The first full world suite reached the interaction test and rejected its obsolete capability-free repair fixture (`world-check-01.log`). The test now asserts unknown capability metadata disables submission, then explicitly enables synthetic repair while leaving inference disabled. The focused interaction test and command transport fixture pass (`interaction-focused-01.log`, `commands-focused-01.log`); the transport fixture verifies six intended POSTs, GET reconciliation, and no worker credential. Runtime policy was not weakened.

The corrected full `mise exec -- just check-world` completed with exit0 in `world-check-02.log`, including the command transport fixture after all headless world checks. Backend03 remains available for the parent task's standalone qualification.
