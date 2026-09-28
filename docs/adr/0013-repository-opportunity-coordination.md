# ADR 0013: Durable repository opportunity coordination

Status: accepted

Date: 2026-09-28. Owner: Core/runtime. The operator requested implementation of
remaining autonomy needs and a shorter iteration trial after the contract foundation.

## Decision

Keep Core as the single mission/authority owner. Add a bounded discovery ledger
(SQLite migration 10 / PostgreSQL migration 8) for exact repository, revision,
capability, build, source digest and candidate/no-change/unavailable observations.
Core orders eligible opportunities using authored capability priorities and stable
identities. Admission still passes through existing policy, reservation and
independent grading gates. No monitored repository or model can create authority.

Add isolated memory-key and logger-level behavior packages to the existing algent
pilot, with separate trusted observation harnesses/public regressions and Core
expected values. No dependency installation, networked sandbox or new repository
write target is introduced. The existing workflow remains compatible; contract
and build identities distinguish capabilities. Broader operational identity and
unattended reliability are qualified separately, not inferred from metadata.

Shorten default development trials to a maximum of 15 minutes, ending earlier
when the predeclared control suite completes. A repeated two-hour soak is optional.
Synthetic controls establish wiring/recovery, never statistical agent capability.

## Alternatives and recovery

Keeping discovery only in worker memory loses no-change/unavailable decisions on
restart and offers no durable prioritization. A separate scheduler service would
duplicate Core/Temporal ownership. A Core-owned indexed identity ledger is the
smallest persistent boundary. Records are retained with explicit capacity rather
than silently pruned or reclassified. SQLite/PostgreSQL migration versions and
checksums reject incompatible rollback; restore a pre-migration backup only after
reconciling external effects. No live migration or activation follows from this ADR.

Review again before increasing repository authority, changing sandbox dependencies,
introducing qualified build promotion, multi-writer publication or indefinite
retention. Dedicated GitHub App setup remains an operator-account dependency.
