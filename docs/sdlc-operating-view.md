# SDLC operating view

Status: accepted

Implemented source-checkout UI, 2026-09-28.

Open Field Command → SDLC missions by pointer or keyboard. Core's current admission
reason appears above the mission selector. The installed-capability disclosure
shows supported work and exact catalog/coordination records. Disabled, expired,
reserved and unknown admission states remain distinct.

Select a mission and open **Inspect pinned contract, crew assignments and
dependencies**. This shows the mission's immutable contract, planned task/crew
assignments and the evidence required for each handoff. Retained evidence is not
a success verdict or proof that the crew member is currently executing. The
mission's full technical ledger remains available below the readable evidence.

PR lifecycle checkpoints retain their exact observed head and time. They do not
replace independent verification or GitHub Actions outcomes. Unknown/old records
are labelled explicitly; a stale connection holds commands while keeping the last
known evidence inspectable. Reconnect preserves the selected mission.

The [capability contracts](repository-capabilities.md) remain Core-owned. This
view adds no repository authority, dispatch, merge permission, XP or promotion.
See the [native and focused evidence](../evidence/world/sdlc-coordination-20260928/README.md)
for covered layouts and remaining live/export qualification limits.
