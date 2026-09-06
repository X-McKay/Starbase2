# ADR 0006: Read-only field agents and reviewed episodic memory

Status: accepted

## Decision

Add Watchkeeper (scoped Kubernetes workload observation and maintenance advice)
and PR Reviewer (a local review draft for one configured GitHub PR) to the
existing Python worker and Rust core. Additive V4 workflows and API records leave
V1–V3 workflows intact. Existing Survey Command and communications facilities
accommodate both characters; neither a new service nor a building is required.

Use direct, bounded HTTP GET adapters for two small provider surfaces. Kubernetes
credentials authorize only namespaced pod/deployment reads. GitHub credentials
need pull-request and contents read access. No repository checkout, configuration
execution, cluster mutation, GitHub comment, approval or merge is implemented.
MCP/agentgateway may replace these adapters when a concrete routing or identity
need warrants that dependency.

At the user's request, introduce Graphiti 0.30.1 with FalkorDB as an optional
persistent memory projection. Use its structured EpisodicNode and FalkorDriver
APIs rather than a new graph abstraction. The core owns approval, revocation,
provenance and immutable per-run memory snapshots in SQL. The graph is scoped by
installation, agent and target. Retrieval checks exact episode content and
provenance against the ledger. Missing graph records can be rebuilt; conflicting
records fail closed. Memory cannot award XP or change permissions.

Only operator-approved findings enter recall. Transcript extraction, embeddings,
semantic entity search and automatic belief promotion are deliberately absent.
This establishes persistence and review controls, **not evidence that graph
retrieval improves agent quality over SQL**. A paired evaluation must justify
richer memory before it influences production decisions. SQL alone would suffice
for today's exact-match recurrence check; the Graphiti integration is an explicit,
replaceable experiment requested by the owner, not a scalability claim.

## Storage and deployment

SQLite development schema becomes V4; production PostgreSQL has a separate V2
migration after its unchanged V1. The existing migration job and scoped grants
cover the new ledger. Ordinary PostgreSQL startup refuses an unmigrated schema.
Restore/rollback remains forward-compatible-image or restore-into-empty-database;
there is no destructive schema downgrade.

Use FalkorDBLite 0.5.0 for repeatable local tests, with a persistent file and a
loopback listener. Production is intended to reuse a separately qualified Kubani
FalkorDB service. The generated production bundle keeps field work and memory
explicitly disabled. Service discovery, scoped credentials, network policy,
transport trust, memory retention and target-specific provider qualification
remain activation gates. No production service was changed by this decision.

## Evidence and limitations

The [field agent guide](../field-agents.md) records commands, tested behavior,
limits and remaining qualification. Durable workflow replay, approved recall,
restart persistence, revocation, tamper rejection and recurring duty pause are
exercised locally. Model advice is explicitly unverified. Linux sandbox
qualification is a separate boundary; read-only field analysis never executes
candidate code and does not substitute for that qualification.
