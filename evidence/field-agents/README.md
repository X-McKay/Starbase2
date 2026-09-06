# Field-agent implementation evidence — 2026-09-06

This is local development evidence, not a production deployment or a comparative
quality certification. No cluster mutation or GitHub publication occurred.

| Surface | Evidence | Result |
|---|---|---|
| Repository checks | [Final repository log](repository-check-final.log), [final Python checks](python-final.log) | 32 Rust tests; 43 Python tests; lint/type checks; four contract versions; documentation checks |
| PostgreSQL | [Final PostgreSQL tests](postgres-tests-final.log), [deployment rehearsal](deployment-rehearsal-second.log) | State machines, migration/grants, denied ledger edits, backup/restore and owned teardown passed on disposable localhost PostgreSQL 18.3 |
| Durable field work | [Final integration](integration.json), [log](integration-summary-api.log) | Synthetic cluster and PR inputs, real Temporal/FalkorDB; restart persistence, approval/revocation, cancellation, duty timer restart/pause and replay passed |
| Real GitHub adapter | [Public PR evidence](github-live.json) | getzep/graphiti PR 1814; two changed Python files, pinned identities, no configured-rule findings; no source execution, credentials or inference |
| Optional model | [One-call pilot](integration-inference.json) | Qwen3.6-35B-A3B-NVFP4 on llm.almckay.io; 741 input / 204 output tokens, 28.551 s; cost unavailable; advice remains unverified |
| Memory tampering/scope | [Memory check](memory-check.json) | Real FalkorDB restart persistence, tamper rejection and cross-agent rejection; installation separation also checked in Python tests |
| Native UI | [World checks](world-check-final.log), [command checks](world-commands.log), [compact footer](world-crew-footer.log) | Keyboard inspectors, reachable characters, fixture/offline semantics and compact large-text footer passed |
| Browser | [Browser result](browser-check-async.log), [host test recipe](browser-check.cjs) | Synthetic labels, paused/offline controls, asynchronous detail/source inspection, no script errors |
| Sandbox guest | [Platform probes](../sandbox-qualification/darwin/probes.json), [crash probes](../sandbox-qualification/darwin/crash.json) | All isolation/resource/timeout/cancellation checks and cleanup passed in Linux microVMs on this Mac; coordinator-only loss stopped after 10.533 s |

[Current fixture builds](builds.json) bind the Python sources, target scope, prompt,
analyzer binary, lockfile and memory policy. The one-call model pilot predates the
final snapshot-size/installation-scope refinements; those did not change its prompt
or model request but the pilot is not presented as a final-build quality evaluation.
Raw local SQL/Temporal files include development tokens and remain under `.local`;
they are not copied into this evidence directory.

Earlier failed logs are retained. The dependency's `bin/falkordb.so` shadowed the
Python package when invoking `pytest` as a console script; `python -m pytest`
corrected the entry-point path. A migration test expected SQLite V3 instead of
V4. The browser test initially checked detail text before its asynchronous request
completed. The first rehearsal invocation lacked PYTHONPATH; the documented `just`
recipe supplies it. Later named logs record the corrected runs.

The Linux host `sparky` has KVM and the pinned upstream archive checksum passed.
Copying the private sandbox adapter and probes was rejected by automatic approval
review pending explicit authorization. No private repository files were transferred.
A Docker Hub pull on that host separately failed TLS hostname verification; TLS
checks were preserved. Neither KVM availability nor local guest tests qualify that
host. Kubernetes observation is tested with synthetic HTTP inputs, not live cluster
credentials. Production field work, memory and sandbox repair remain disabled in
the generated bundle.

Visuals: [Watchkeeper](watchkeeper.png), [PR Reviewer at compact large text](reviewer-compact-final.png),
[journal and reviewed memory](journal.png). These show retained synthetic work.
