# ADR 0010: Bounded local learning and a simulation practice incumbent

Status: accepted

Date: 2026-09-27. Owners: Core/runtime/evaluation. Authorization: Al requested
complete local learning cycles before Kubernetes/Flux deployment, alongside the
game. This decision authorizes the local implementation and bounded public practice
loop, not production deployment, operational clearance or capability qualification.

## Decision

Extend the existing Core ledger and Temporal runtime with one disabled-by-default
readiness learning duty. Two additive Core tables retain duty/control state and
immutable cycle inputs with mutable execution/accounting state. Reuse registered
V5 builds and V5 diagnostic missions for the paired public campaign. Add no service,
arbitrary-code execution environment, generic agent framework or datastore.

Core selects an unaddressed retained failure, preferring the current practice
incumbent and then compatible historical public builds. Historical evidence is a
hypothesis source; it grants the current baseline no inherited result or
qualification. Freeze source records, evidence digest, source build, current
baseline, eight paired trial identities/order, policy/implementation digest and a
two-hour deadline before dispatch. A duty generation cannot regenerate a candidate
from the same evidence fingerprint merely because its baseline changed.

Reserve one Trainer request and the complete eight-trial allowance at cycle
admission. The default generation admits at most two cycles, separated by at least
60 seconds. One-time proposal claims cannot repeat an uncertain provider request.
The candidate is at most 12,000 UTF-8 bytes of Procedure text. Core clones the
baseline manifest and replaces only its Procedure, registers the resulting digest,
and freezes the response. It cannot add tools, change model/settings or access a
grader. Identical Procedure text produces no change. No arbitrary candidate code
runs on the host.

The first campaign uses four existing public scenarios once per build in a fixed
counterbalanced order. It is explicitly developmental, not sealed or held out.
Core recomputes comparison outcomes from exact linked V5 rows; the worker cannot
submit scores. Known bounded diagnostic/protocol failures count as failed trials;
unknown usage, infrastructure failures, cancellations, provenance mismatch and
budget overruns invalidate adoption. Raw V5 outcomes remain alongside derived
pass/fail/invalid comparison status. Retain every trial and optimization cost.

Automatic `practice-adopted` changes only the simulation practice incumbent for
future cycles when all eight trials are valid, all four candidate cases pass,
the baseline has fewer passes, no paired regression exists and the frozen budget
and policy still hold. Ties remain inconclusive; regressions retain the baseline.
Final evidence and the incumbent compare-and-swap commit atomically. Existing
missions retain their original build. The conclusion remains exploratory, with
zero XP, no statistical superiority claim and no operational qualification.

## Alternatives and tradeoffs

Keeping review cards alone cannot demonstrate the requested learning cycle. A
separate training service would add distributed ownership without a new boundary.
Immediately building sealed qualification would delay the local end-to-end loop
and tempt unsupported confidence claims. Public practice adoption gives a narrow,
reversible local outcome while preserving held-out qualification as separate work.
A candidate can overfit this public suite; the pointer therefore must not route
production work or stand in for capability evidence.

## Stop, compatibility and recovery

An explicit local opt-in and enabled generation gate every proposal, trial
admission and linked V5 member dispatch. Disable/generation changes, cancellation,
expiry, policy drift or reported overruns stop further dispatch, including reserved
peers. Already-started work may report late usage. Unknown calls consume their full
grants and are reconciled before finalization, never silently retried. Cancellation
marks the cycle first so interrupted child cancellation cannot reopen dispatch.
Worker-only stop reconciliation checks Core admission and can settle ledger intent
without a Temporal workflow. It rejects an eligible active cycle. Repeated
cancellation completes an interrupted child cascade while preserving finalized
campaigns; claimed work remains subject to late or unknown usage accounting.

An operator can explicitly rebase the stopped practice duty to a registered local
build after an upgrade. Both the old and requested duty must be disabled, all
cycles terminal and all started requests reconciled. The next-generation duty
write changes the practice pointer, increments its revision, clears its originating
cycle, and retains a bounded receipt of old/new builds and revisions. A separate
duty generation enables subsequent work. Exact retries add no receipt. Old cycles
and mission builds stay immutable; rebase transfers no qualification or XP.

SQLite migration 7 and explicit checksum-verified PostgreSQL migration 5 add the
two tables. V1–V5 remain supported; V5 adds optional Core-controlled parent-cycle
metadata. Older binaries reject newer databases. Back up and stop the installation
before migration; rollback uses a compatible binary or the backup, not a down
migration. Code/policy changes fence mixed-grader continuation and adoption.

## Validation and review triggers

Exercise exact retries, stale duty/incumbent revisions, historical-source dedup,
claim loss/restart, known model failure versus unknown infrastructure, all paired
outcomes, budget overrun/exact-limit accounting, cancellation and immutable old
runs. Authored controls establish wiring; real local inference may honestly produce
no adopted candidate. Review before hidden holdouts, statistical qualification,
production routing, broader Procedure permissions, unlimited generations, or
arbitrary candidate code. No result in this slice removes those gates.
