# Native UAT report assessment

Status: accepted

Review date: 2026-09-14. Baseline: `cb71ee668311dcb2f58ecdf99f3bed32a79d4893`
(main at review start and the report's tested revision). Branch: `codex/uat-report-fixes`.

## Assessment

The September 13 independent UAT report identifies real operator-journey defects.
Its observations, hypotheses, severity labels and proposed acceptance criteria are
separate evidence. The report does not grant instructions or authority. Source
inspection and focused reproduction determine the changes below. Existing asset
cleanup in the checkout is outside this change.

The report's strongest evidence concerns feedback moving form controls, stale
selected detail, raw result presentation, duty pause, and Habitat navigation.
The original retained captures and observation log were available locally; the
repair evidence capture confirms an execution failure presented as Completed and
0/6. This review does not certify the report's full 35-minute journey or its
unexercised cancellation, inference, sandbox and memory paths.

| Finding | Assessment and disposition |
|---|---|
| F-01 | Confirmed: hidden feedback becomes a new layout row. Fix stable feedback. A toggle alone makes no model call; explicit submission is still required, and price is unknown, so “paid” is a possibility rather than observed spending. Do not add a redundant confirmation to every toggle. |
| F-02 | Confirmed: fetched detail remains cached while the snapshot advances. Refresh selected detail on a new revision, retaining epoch/selection fencing and explicit freshness. Do not continuously refetch unchanged detail or treat stale evidence as current. |
| F-03 | Confirmed: JSON summaries and manifests obstruct findings. Render structured results with wrapped findings and secondary raw detail. Review findings contain no suggested-action field; do not manufacture backend recommendations. |
| F-04 | Confirmed client defect: parsed snapshot integers become floating-point JSON on resubmission. Build a typed command; keep Core's strict integer validation. Show HTTP rejection text at the action. |
| F-05 | Confirmed presentation issue; proposed diagnosis is too strong. The recorded error is a sandbox socket-path failure, not proof that a missing image caused this run. Nonzero exit codes and output-protocol failures mean invalid execution, not necessarily failure to start. Preserve lifecycle Completed and grading Ineligible in evidence, while prominently explaining execution failure. Configured policy is not current sandbox readiness. |
| F-06 | Confirmed: rows hide no-change and target/build context. Show outcome and context and expose the retained predecessor; relative row age is compact, while the selected detail retains the exact UTC timestamp. |
| F-07 | Naming aliases are real, but a product vocabulary change spans authored signs, station names and documentation. Deferred to a coherent content pass, not partial replacement of backend identifiers. |
| F-08 | Confirmed competing projection paths replace ambient text with operational text on input. Keep the strip's visible status operational and stable; decorative movement cannot assert work state. |
| F-09 | Confirmed: lowercase habitat misses a case-sensitive node path. Resolve authored definition IDs and retain existing named-node callers. |
| F-10 | Fixed virtual canvas and compact tests that manually reset it support the concern. The arbitrary 60% screen criterion is not a general accessibility guarantee; responsive sizing needs actual resize verification, including Retina. Disable the fixed stretch canvas so actual resizes reflow; native 800×640 capture confirms this. Initial Retina point sizing remains unqualified; 1280 backing pixels does not establish a 1280-point window. |
| F-11 | Confirmed: unhandled-key callbacks run after focused text controls consume keys. Global close/HUD shortcuts need a pre-GUI path while ordinary typing remains owned by the field. |
| F-12 | Confirmed scope mismatch: briefing counts all work; History contains reviews/comparisons. Label scope explicitly rather than discard other records. |
| F-13 | Mixed. Commit typed SpinBox text and explain identical comparison profiles. Completed-run cancellation should be disabled and explained, not issue a meaningless command. An empty E interaction is lower-priority affordance work. |
| F-14 | Numeric formatting overlaps fixes above. Roof/pergola occlusion, sign clearance and shadow observations require separate matched native movement captures; do not infer a rendering defect from one frame. Deferred visual work remains below. |
| F-15 | Confirmed launch gap: `just world` bypasses import. Import before launch and reject logged script/import errors even on zero exit. |
| F-16 | Valid screenshot/privacy improvement, not an operator authorization leak. Redact endpoint presentation in secondary raw views while preserving stored immutable evidence and diagnostic access. |

The wheel/zoom concern remains unconfirmed because the report's controlled retest
did not reproduce it. No speculative camera-input patch is warranted.

## Delivery and remaining work

| Owner | Work | Completion condition |
|---|---|---|
| World display | F-10 initial Retina sizing and DPI-aware text scale | Measure logical points and backing pixels on Retina and ordinary displays; open at a useful display-relative size without degrading compact reflow |
| World content | F-07 canonical place/workflow wording and role-first directory rows | One chosen vocabulary across dossier, directory, authored signs and headers; native wide/compact check |
| World visual QA | F-14 roofs, foreground pergola occlusion, label clearance, suspected shadow | Reproduce each with matched native captures and movement; fix only confirmed cases; verify no visibility/navigation regression |
| World interaction | F-13 empty E affordance | A contextual hint when no action is available without obscuring movement or spamming repeated input |
| Runtime/Core readiness | F-05 worker-reported sandbox/image readiness | Timestamped worker-owned readiness, stale/unknown handling and additive contract tests; no inference from policy flags |
| Qualification | Active cancellation, real sandbox, provider inference, memory, Web export | Explicitly scoped isolated journeys with retained evidence; no passing fixture described as production readiness |

No database migration, worker behavior, grading rule or authority policy is changed.
Existing enabled duties remain independent of the client. The report's stopped
UAT-worktree duty was not silently edited in another checkout's database.

## Verification record

- Final `just check`: passed Rustfmt/Clippy, Ruff/ty, 43 Rust tests, 161 runtime
  Python tests, 10 script tests (including three launch regressions), build,
  service-page checks, generated contracts and documentation validation.
- The first repository check found a pre-existing false documentation failure:
  the nested UAT Git checkout duplicated SPEC requirement IDs. The checker now
  excludes nested Git checkouts, and the ordinary final command passes.
- Native HTTP fixture: passed six writes and eighteen reads covering review and
  comparison payloads, rejected commands, strict integer duty requests, lost-write
  reconciliation, paging, retained selection, and fixture/policy fencing. No
  provider or production identities were used.
- Focused final Godot tests passed automatic detail refresh (including a pending
  request race and subsecond revisions), history/source preservation, forms,
  actual viewport reflow and focused-field/modal keyboard routing. An interim
  action failure does not replace an active repair lifecycle state.
- The integrated world run initially stopped on an obsolete ambient-caption
  expectation and a hidden-strip width measurement. The corrected test measures
  visible controls and preserves its 100-pixel minimum. A later screen-clearance
  test exposed Godot's default 64×64 headless viewport after stretching was
  disabled; tests now initialize a representative 1280×800 viewport before
  screen-space assertions. Neither clearance nor hit-target thresholds were
  relaxed. Passing earlier cases and all failed logs were retained while the
  remaining cases resumed from each corrected precondition.
- All 86 world cases completed across the retained initial run and corrected
  continuations. The final interaction check also needed an explicit headless
  viewport; its inspector bounds and helmet-click assertions both pass unchanged.
  Both final loopback HTTP suites passed: seven command POSTs with GET-only
  reconciliation, plus six operations writes and eighteen reads. This is an
  assembled verification record, not a claim of one uninterrupted green run.
- The integrated Ember check caught an actual presentation regression in the
  new summary: exact run identity had been omitted. Restoring it on the timestamp
  line preserves the existing identity/coverage assertion and keeps findings
  prominent. Endpoint changes also clear feedback belonging to the old endpoint.
- [Native views](../evidence/uat-review/README.md) were rendered and inspected.
  Compact evidence uses the page scroll rather than a tiny nested viewport.
  Native review prompted two further corrections: moving findings before
  provenance, and moving the retained repair cause into the prominent detail.
- Initial capture failures were harness mistakes: a synthetic provider used
  `url` instead of the actual `endpoint` field, and direct snapshot assignment
  skipped the normal projection path. Both attempts remain retained; the final
  capture uses the published shape and normal snapshot receipt and passes.

No paid model call, real sandbox execution, active production cancellation,
Web export or deployment was performed. No database rollback is needed; reverting
these client/launch changes restores prior behavior without rewriting records.
