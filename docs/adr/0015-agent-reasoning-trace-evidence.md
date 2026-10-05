# ADR 0015: SDLC agent reasoning traces as bounded operator evidence

Status: proposed

Date: 2026-10-04. Decision owner: Al McKay (X-McKay). Proposed by the
implementation assistant; not accepted. Nothing in this record is implemented,
and acceptance would authorize local implementation only. It would not authorize
deployment, migration of a live installation, spending, or any external action.

## Decision question

How should Core retain enough of each V7 SDLC member run that the operator can
answer "why did the crew take this step", without weakening grading, authority,
privacy or snapshot size?

## Context: what develop records today

All paths are under `services/`. Line numbers are from develop at `c72e65e`.

- V7 tool-session members record the structured output, the served model name,
  token usage, usage completeness, elapsed time, per-request metadata (request
  number, status, finish reason, latency, tokens), tool receipts and the profile.
  See `runtime/starbase_runtime/agents/sdlc/factory.py:63-82` (request rows),
  `:217-228` (success) and `:232-243` (failure).
- Tool receipts keep `input_digest` (a digest of the arguments), before and after
  candidate digests and the tool result. They do not keep the arguments
  themselves (`runtime/starbase_runtime/sdlc_workspace.py:178-190`).
- The PydanticAI message history is never kept. The runtime never calls
  `all_messages`, `new_messages` or `capture_run_messages`. `factory.py:10`
  imports `ModelMessagesTypeAdapter` only to size budget reservations (`:56`).
- The `tools-thinking` profile sets `enable_thinking` and a larger output limit
  (`agents/sdlc/definition.py:26-39`). Any thinking parts in the replies are
  discarded with the history. The process default is still `legacy` (`:8`),
  which does not use this factory (`sdlc_pilot.py:366-369`).
- `ModelRetry` feedback from the output validator (`factory.py:156-173`) goes
  back to the model but is never recorded. The pinned PydanticAI 2.40.0 keeps
  this feedback in the history as `RetryPromptPart`.
- V5 and V6 already keep the raw model reply. Joint tasks store
  `trace.response` (`runtime/starbase_runtime/joint_activities.py:182-188`) and
  the Trainer does the same (`learning.py:194-199`). V5 traces reach the operator
  through the full mission records in the snapshot ([joint view](../joint-operations-view.md)).
- Monetary cost is always `None` for model calls (`inference.py:92`,
  `field.py:214`, `field.py:221`, `repair.py:119`). The only zero is the
  deterministic repair control, which makes no calls (`repair.py:134`).
- `GET` requests that are not under `/internal/` skip authentication
  (`core/src/operations_api.rs:44-48`). Writes need the operator session cookie,
  and `/internal/` routes need the worker bearer token. `/v7/snapshot` embeds every
  full mission record, including its events (`core/src/sdlc.rs:292-295`). Each
  event can be up to 128 KiB, with at most 100 events per mission
  (`sdlc.rs:495-496`).
- Missions are never pruned. Admission stops at 100 retained records
  (`sdlc.rs:162`, `retention_capacity`).
- Trainer reports are derived from `/v7/snapshot` ([SDLC improvement](../sdlc-improvement.md)).
  V6 Trainer context already excludes raw traces ([learning cycles](../local-learning-cycles.md)).
- No general evidence classification is implemented. [ADR 0001](0001-starbase2-foundation.md)
  (proposed) calls for classifying evidence and storing "redacted operational
  summaries, not raw private reasoning". The only implemented redaction profile is
  the Python source mask `literal-and-comment-v1` (`runtime/starbase_runtime/review.py:28`,
  checked in `core/src/operations.rs:274`).

## Proposed decision

1. **What to capture.** For each V7 tool-session member run (lead, implementer,
   reviewer, and every revision round), capture the following:
   - the complete PydanticAI message history from `capture_run_messages()`, so
     failed and cancelled runs are captured too;
   - tool-call arguments and tool returns;
   - thinking parts as the provider returns them;
   - `RetryPromptPart` feedback, including output-validator `ModelRetry` text.

   Tool receipts keep their existing digests. The trace links each tool call to
   its receipt `sequence` and `input_digest`, so the two records can be checked
   against each other. Single-response `legacy` members keep their raw reply in
   the same envelope.
2. **Classification and redaction.** Define a minimal trace classification
   instead of waiting for a general scheme.
   - Every trace carries `classification` (`synthetic-public`, `pilot-repository`
     or `private-repository`, taken from the Core capability record and never
     from the model), a `redaction` profile identifier, and a list of redacted
     spans.
   - Profile `trace-secrets-v1` removes pinned credential patterns (token
     prefixes, PEM blocks, bearer headers, `key=`/`password=` assignments) from
     every text part. It replaces each match with a typed marker and the digest
     of the removed value.
   - Repository source inside a `private-repository` trace also passes through
     `literal-and-comment-v1`.
   - A redactor error discards the trace body and records `redaction_failed`. It
     never stores the body unredacted.
   - Credentials are already kept out of model context
     ([ADR 0011](0011-bounded-repository-sdlc-pilot.md)), so redaction is defence in
     depth, not the primary control. Thinking text is classified `model-reasoning`
     inside the trace and labelled unverified in the UI.
   - For SDLC members, this partly supersedes ADR 0001's guidance against
     retaining raw private reasoning. That conflict must be settled before this
     ADR can be accepted.
3. **Size caps.**
   - Each part (a message text, tool argument, tool return or thinking block) is
     capped at 16 KiB. A larger part keeps its first and last 8 KiB, the original
     byte length and the SHA-256 of the full part.
   - Each member trace is capped at 512 KiB of serialized JSON, and each mission
     at 4 MiB. When a cap is reached, the oldest tool returns are truncated first,
     then thinking. The final output and retry feedback are kept.
   - Truncation sets `truncated: true`. The theoretical uncapped size is about
     2.5 MB per member, from 32 calls, a 48 KB input and a 32 KB output
     (`sdlc_workspace.py:23-30`).
   - The worst case for retained traces is 100 missions × 4 MiB = 400 MiB.
4. **Storage.** Traces are Core-owned evidence in a new additive Core table,
   added by an additive SQLite/PostgreSQL migration whose number is set at
   implementation time. It stores one row per mission, member and round, with
   the digest, classification, byte count, capture state and body.
   - The worker posts each trace once to `/internal/v7/missions/{id}/traces/{key}`
     using the existing worker bearer token. An identical replay returns the
     stored row and a conflicting replay is rejected, as for SDLC events.
   - Traces never enter Temporal histories, activity results, Core mission events
     or the `body` JSON of `sdlc_missions`. Worker code posts a trace directly to
     Core before returning the existing small activity result. This follows
     "store large traces outside workflow histories" ([evaluations](../evaluations.md)).
   - Failing to post a trace never fails or retries the mission. The reference
     then records `capture_failed`.
5. **Serving.**
   - Traces are served only from a detail endpoint,
     `GET /v7/missions/{id}/traces/{key}`.
   - `/v7/snapshot`, `/v7/missions/{id}`, mission events and any later push
     channel carry only a reference: key, state, digest, bytes, classification
     and `truncated`. No SSE or WebSocket channel exists today, and none is added
     here.
   - Reference states are `captured`, `truncated`, `redaction_failed`,
     `capture_failed`, `not_captured` (older missions or a disabled feature),
     `purged` and `unknown`. The UI must show each state distinctly. A missing
     trace never reads as "no reasoning".
   - The UI's "why this step" opens the trace from a step's tool receipt or
     request row. It is reachable by keyboard and through the structured
     operations view.
6. **Access.** The trace endpoint is the first `GET` route that requires the
   operator session cookie, with the same `Origin` and `Sec-Fetch-Site` checks as
   writes. Without them it returns 403. Other public GETs keep their current
   behaviour, which this ADR does not decide. The native client already holds the
   cookie in memory. The worker credential cannot read traces.
7. **Retention.**
   - A trace body is kept for 30 days after its mission reaches a terminal state,
     then purged. A purged trace leaves a tombstone with the digest, byte count,
     classification and purge time.
   - Purging never touches the mission record, events, grading or receipts, so
     mission evidence keeps its current lifetime. Traces never count toward the
     100-mission `retention_capacity`.
   - The operator can purge one mission's traces early. Missions are never
     deleted today; if mission deletion is added later, it removes that
     mission's traces too.
   - Backups include trace rows. Restoring a backup restores bodies that were
     purged after it was taken, so the purge job runs again after any restore.
8. **No feedback into grading or authority (SBT-006, SBT-010).**
   - `grade_for` (`sdlc.rs:222`), verification, publication, admission, memory
     proposals, XP, qualification, Trainer context and `sdlc_improvement`
     reports never read the trace table.
   - Traces are absent from the snapshot that Trainer reports are built from.
   - The model never sees an earlier trace as input.
   - The trace is a narrative from an untrusted model. Showing it explains the
     step; it does not verify it.
   - Tests must show that grading outputs and snapshot bytes are identical with
     trace capture on and off.
9. **Cost.**
   - Core computes `cost_usd` from retained per-request usage and a pinned,
     digest-identified price table under `config/`. Each entry is keyed by
     provider and exact served model name and gives input, output and, where
     billed, reasoning or cached token prices with an effective date.
   - The table digest is recorded with each cost. The worker never submits a
     cost.
   - The result is `null` with a reason (`local_model`, `unpriced_model`,
     `incomplete_usage` or `unknown_request`) unless every request returned
     usage and the model matched a priced entry. Local models, including the
     current Qwen endpoint, are always `local_model`/unknown, never zero.
   - Zero is valid only when no provider call was made, as in the existing
     deterministic control.
   - V2–V6 cost fields stay unchanged until they are migrated separately.

## Alternatives considered

- **Keep the current approach** (digests and metadata only). It stores nothing
  sensitive and adds no storage. It cannot answer "why", it hides retry
  feedback, and it leaves `tools-thinking` impossible to judge from evidence.
- **Store everything unredacted in the mission body**, as V5 does. This is the
  simplest change. It would make the public snapshot several MiB, expose model
  reasoning and source without authentication, and feed traces into Trainer
  reports through the snapshot.
- **Use an external tracing backend** such as OpenTelemetry/Logfire or Langfuse.
  This gives a good viewer, but it is a new service with its own credentials and
  retention, outside Core's evidence authority and Kubani recovery. It could be
  reconsidered when there is a cross-service tracing need.
- **Keep thinking only as a summary.** This fits ADR 0001's wording, but a model-
  written summary of its own reasoning is another unverified output and loses
  the retry and tool detail that matter most.

## Consequences and tradeoffs

- Core gains a growing private-content store, a purge job and its first
  authenticated GET.
- Traces may contain repository source and model speculation. Redaction is
  pattern-based and best effort, so `private-repository` traces stay local until
  provider and classification policy are qualified.
- Capture adds one bounded POST per member and some serialization time. This
  has not been measured.
- Whether Qwen through the current endpoint returns `reasoning`/`reasoning_content`
  (which PydanticAI maps to `ThinkingPart`) or inline `<think>` text has not been
  checked. Without that check, "thinking captured" cannot be claimed.
- Rollback: disable capture with a worker setting, and the references become
  `not_captured`. The additive table can stay, or its bodies can be purged. Older
  binaries reject the newer schema, as for previous migrations.
- Exit path: replace the table with an external tracing backend behind the same
  reference contract.

## Completion condition

The trace work is complete when this ADR is accepted and all of the following
hold in local and CI evidence:

- Capture works for success, `ModelRetry`, validation failure, budget exhaustion
  and cancellation.
- One real `tools-thinking` run shows whether thinking parts arrive.
- Secret-pattern fixtures are redacted, and a redactor fault records
  `redaction_failed`.
- Cap and truncation tests pass.
- The detail endpoint returns 403 without the operator cookie.
- Snapshot bytes and grading are identical with capture on and off.
- Purge leaves a tombstone, and the purge job runs again after a restore.
- Cost is `null` for the local model and computed for a priced fixture model.
- The native "why this step" journey works by keyboard and in the structured
  view, with every reference state shown.

Until then the work stays in the [delivery plan](../roadmap.md).

## Review triggers

Revisit before any of the following:

- capturing traces for private repositories with non-local providers;
- exposing traces beyond loopback;
- extending capture to V2–V6, or moving V5 traces out of the snapshot;
- feeding traces into Trainer or evaluation context;
- raising the caps or the retention period;
- adopting an external tracing backend.
