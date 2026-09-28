# ADR 0012: Independent PR verification and bounded correction

Status: accepted

Date: 2026-09-28. Owner: Core/runtime/World. The operator accepted the plan to
continue the disposable algent pilot using isolated verification, separate GitHub
statuses and reviewed PR revisions despite the GitHub Actions account blocker.

## Decision

Extend the existing V7 mission with bounded immutable-input verification records,
not another service or an alternate CI dashboard. Each child binds the exact PR
head, worker build and current standing policy. A new additive Temporal workflow
retains restart/replay support for the original mission workflow. The existing
JSON storage gains additive child records; no database migration is needed.

Use the current Python 3.13.5 microVM boundary to run the independent seven-case
oracle and trusted public regression suite. The public test artifact on the PR
must match the trusted version; changes require operator investigation rather
than silently evaluating weaker tests. Core derives pass/fail/infrastructure
outcomes. Publish the separate `starbase/persistence-regression` GitHub commit
status, with durable one-shot pending/result claims and uncertain-effect
reconciliation. Preserve the blocked Actions result and human merge decision.

Only a reproduced code failure may trigger a diagnostic lead handoff followed
by up to three implementation/review rounds. A candidate must improve the independent oracle, pass the public suite,
and receive independent review before the adapter updates the existing pilot
branch without force and posts a COMMENT review. Only persistence source changes;
tests, workflows and other source files remain unchanged. The next observed head
receives a new verification, never success inherited from its predecessor.

## Authority and compatibility

A separate opt-in, `STARBASE_SDLC_VERIFICATION_ENABLED=true`, enables new
admissions/effects. It is disabled by default. The local supervisor additionally
requires private `verification.json` declaring enabled=true and the exact algent
repository. Current enabled publication policy must be unexpired; its generation
binds each new child. Policy changes, cancellation, stale head or closed PR fence
effects. Older parent policy generations do not confer child authority.

Keep at most sixteen children per parent and one active child across the pilot.
Retain failures and uncertainty, with no automatic retry of the same head/build
or retention deletion. This deliberately bounds development operation; indefinite
monitoring and retention require a separate qualification. No credentials enter
candidate execution or model context. There is no merge, production deployment,
new repository scope or account billing change.

The REST ref update checks the expected head immediately before a non-force
update. Divergent concurrent updates fail rather than being overwritten. REST
does not provide atomic expected-head compare-and-swap; a future broader
multi-writer deployment should adopt a provider-supported atomic mutation.

## Alternatives and validation

Waiting for Actions billing would block useful development without improving the
already qualified local isolation boundary. Installing a GitHub runner would add
another credential/execution surface and account dependency. Independent status
publication reuses the trusted verifier and remains removable later; Actions can
resume alongside it.

Validate raw-result grading, public-suite failure, malformed observations,
infrastructure abstention, source/head drift, cancelled/revoked authority,
duplicate/lost effect acknowledgements, hard restart and Temporal replay. Use
explicitly synthetic controls before real algent operations. A labelled regression
drill on the authorized disposable branch demonstrates one concrete repair path;
it is not a general reliability benchmark. World shows exact-head verification
and infra/code outcomes separately from Actions. No XP or promotion is implied.
