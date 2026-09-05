---
name: starbase2-agent
description: Add or change a Starbase2 agent capability, build, prompt, skill, tool binding, or memory policy. Use for implementation of agent behavior; use starbase2-evaluate for a comparison campaign alone.
---

# Change a capability, preserve its evidence

Read [agent evaluation semantics](../../../docs/evaluations.md) and the relevant
implemented agent definition. A persistent crew member and an immutable Build
are different entities. Do not bind one character permanently to one model or
require a new subclass or service for every capability.

Define the task, typed output, allowed evidence, tools, budget, and success/no-
change/inconclusive cases. Prefer existing PydanticAI composition over a custom
agent framework. Select budgets from the task; no minimum model-call count,
fixed prompt count, or arbitrary source-line quota.

Make material code, prompt, skill, tool, model, dependency, and memory changes
part of a new build identity. Pin the effective configuration used by a run.
Do not mutate an active run or silently inherit a qualification from its old
build. Personality and cosmetics are presentation unless deliberately included
in an evaluated prompt experiment.

For a tool, specify its input/output schema, target scope, effects, deadline,
retry/idempotency behavior, and external capability requirements. Validate
model-generated arguments in trusted code. A tool description, installed MCP
server, or new skill never grants production authority. Keep reusable provider
credentials outside the candidate process.

Add public scenarios for expected behavior, correct abstention, malformed
inputs, and relevant misuse or injection. Run fake-model checks first. Use
`starbase2-evaluate` for claims about stochastic quality. A missing model endpoint
does not justify inventing a score or secretly falling back to production.

New persistent memory requires provenance, scope, review policy, versioning,
and rollback. Freeze memory during comparisons. Never automatically turn all
transcripts or untrusted source instructions into accepted memory.

Handoff: build diff, capability and authority changes, scenarios/checks run,
quality evidence or explicit uncertainty, and rollout behavior for new versus
already-running work. Runtime agent skills live with builds; development skills
under `.agents/skills` are not automatically loaded into those builds.
