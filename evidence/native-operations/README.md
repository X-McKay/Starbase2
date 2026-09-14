# Native operator UI integrated checks

## Current qualified local artifact

The unsigned standalone macOS artifact at
`.local/reviews/native-operations/20260909-final-05/Starbase2-macOS.zip` passed the
export runner (`export-05.log`). Its provenance, native PNGs and logs are retained
in [package-05](package-05/manifest.json). Root verified current world sources,
runner, archive, executable, PCK and all recorded capture/check hashes. The
extracted app was opened with `operator-world.json`; native window inspection
confirmed the rendered offline review room. Press `R` for Operations.

The latest integrated `just check-world` passed (`world-03.log`) after the compact
layout changes, with no Godot error/parse/timeout markers. All 15 native recorded
walks passed; maximum arrival distance was 0.272 metres against the unchanged
0.45-metre bound, with no observed manual movement input. Airlock checks passed.
Root and an independent reviewer inspected compact, history, briefing and nearby
task-marker captures. At 800×640 with large text, the Start action requires a
normal form scroll; full IDs are available in selected details/tooltips.

Attempts 01–04 remain failed evidence; see [native launch observations](native-launch-note.md).
The intermittent review-exit failure in attempt 04 has no established root cause.
Final05 did not reproduce it and now records per-walk diagnostics. The next
occurrence must be diagnosed using that evidence before a broader reliability
claim. Native capture currently requires supervised foreground activation.
This artifact is an offline UI qualification, not a production activation or a
new real-provider qualification. Backup/restore remains a durable-production
gate, not a gate on this stopped preparation.

## Earlier checks

`mise exec -- just check` passed with exit0 (`check-01.log`). Existing generated-contract integer-format fallback warnings remain; contract and documentation checks passed.

Initial `just check-world` failed at the old `test_field_crew.gd` label expectation and retained the assertion plus bounded timeout (`world-01.log`). The implementation intentionally uses an `Evidence ready` marker. Root corrected the test to assert that marker while separately preserving the Findings outcome and inspector finding-count checks. No runtime policy was weakened.

The corrected complete `just check-world` passed with exit0 (`world-02.log`), with zero Godot ERROR, SCRIPT ERROR, Parse Error or timeout markers. The command transport fixture passed. The new synthetic operations HTTP harness reports6writes and18reads, covering review/evaluation payloads, denied responses, duty lost-response generation reconciliation, more than20 paged runs, retained selection/evidence, and fixture/unknown-policy dispatch fencing. These are synthetic loopback checks, not provider execution.

Prior `.local/live-world-review-03` cleanup was verified: its cleanup event is present and both ephemeral GitHub and runtime token files are absent. The backend is no longer running for this qualification. Root owns the final standalone offline-fixture export and its native visual review.

The independent infrastructure-only candidate at `.local/starbase2-stopped-preparation` passed local Kustomize validation and contains exactly one Namespace, one ServiceAccount and three NetworkPolicies, with no workload, Secret or image reference. Root copied the hashed candidate into `evidence/kubani-namespaces/stopped-preparation`. No Kubani or cluster resource was changed by this work.
