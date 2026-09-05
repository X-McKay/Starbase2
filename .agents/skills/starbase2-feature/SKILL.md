---
name: starbase2-feature
description: Implement or fix Starbase2 backend behavior, including connectors and owned API or persistence changes. Use other focused skills for agent experiments or world-only changes; documentation edits do not need this workflow.
---

# Deliver one observable slice

Read the relevant requirement and [architecture](../../../docs/architecture.md),
then inspect the actual code and commands. Planned directories and commands are
not evidence that an implementation exists. Start from the user's outcome;
do not scaffold the entire service catalog.

1. Identify the owning service and reproduce the unmet behavior with a test
   or bounded local observation. For a defect, preserve the regression case.
2. Change the smallest cohesive owner. Provider SDK types stay in adapters;
   consumers use published contracts, not foreign tables or internal imports.
3. For an API/event change, identify existing consumers, publish a versioned
   schema and shared fixtures, and test the supported rollout window. Generate
   clients from the source contract; do not require unrelated services to deploy
   together for an additive change.
4. For persistence, prove atomic state/outbox behavior, duplicate handling, and
   migration compatibility. For Temporal, test restart/replay and retain code
   needed by open histories. Apply these checks only to affected boundaries.
5. Verify the focused behavior, relevant integration paths, and available
   repository checks. Update the owner documentation and report exact results.

A connector needs bounded payloads, source freshness, stable delivery IDs,
checkpoint recovery, and a fixture without live credentials. It does not need
a new building, agent class, or bespoke service by default.

For a new tool affecting agent behavior, also apply `starbase2-agent`. For a
consequential ownership or trust change, use `starbase2-decision`; ordinary
refactoring stays in this workflow. Existing authorization covers necessary
reversible local work. Do not add a confirmation ritual before it.

Handoff: observable result, owner/contracts affected, validation, relevant
failure/recovery behavior, and remaining limits. Do not run paid evaluations or
live provider operations as an implicit backend test.
