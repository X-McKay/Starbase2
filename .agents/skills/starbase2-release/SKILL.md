---
name: starbase2-release
description: Check Starbase2 change readiness, prepare a release, or execute a specifically authorized publish/deployment. Scale checks to affected surfaces; a readiness review does not itself authorize external actions.
---

# Verify the exact thing being handed off

Read the requested scope, actual diff, available CI, and implemented commands.
Use [delivery stages](../../../docs/roadmap.md) for product maturity, not as a
requirement to complete every future feature before a bounded change can land.

For a repository change, run the relevant deterministic checks, inspect the
final diff, and state what was verified. Documentation-only work needs link and
status validation, not a live-model preflight, cluster access, or benchmarks.
Do not rerun flaky checks until green or invent evidence from configuration.

For a runtime release, bind tests, provenance, dependency evidence, contracts,
migrations, retained Temporal histories, and rollback to the exact artifact
digests. Agent changes also require the applicable evaluation evidence; UI
changes require actual visual verification. No unrelated approval ceremony.

For deployment, first resolve the target installation and existing task
authorization. Prepare the exact immutable artifact/manifest diff, policy,
identity, resource, observation, and recovery plan before seeking any missing
final approval. Authorization already granted for this action persists.

Kubani owns environment activation. Inspect its current instructions and target
state; do not port old overlays, identities, or generated promotion files.
Verify worker/API authentication separately from Temporal Web login. Keep
effects disabled through uncertain restore or ledger reconciliation, and retain
an independent stop/recovery path. No production experiment as a smoke test.

After an authorized action, verify the actual provider or Flux result and the
observable behavior. Timeout after dispatch is uncertain; reconcile before
retrying. Preserve rollback and old worker versions until their supported
compatibility window ends.

Handoff: ready/not ready/unable to determine for the requested scope, checks
and revisions, remaining gaps, and any action actually performed. Readiness
for a documentation commit is not readiness for the product's deployment.
