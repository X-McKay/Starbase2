# Development skills redesigned for Starbase2

Status: proposed

Owner: Al McKay (X-McKay)

Reviewed: 2026-09-05 UTC

## Decision

Author six small repository skills around recurring decisions and real work.
Do not import either predecessor's skill tree. Keep high-value invariants in
the charter and detailed product semantics in the owning docs; a skill explains
how to do a task without reciting the whole repository.

The files below are present. They guide work against the proposed design and
explicitly require inspecting what is implemented. Runtime command examples
are not presented as available until the walking skeleton adds them.

| New skill | Responsibility |
|---|---|
| [starbase2-feature](../.agents/skills/starbase2-feature/SKILL.md) | One backend slice; connectors, contracts, persistence and durability as affected |
| [starbase2-agent](../.agents/skills/starbase2-agent/SKILL.md) | Composable capabilities, immutable builds, tools and memory policy |
| [starbase2-evaluate](../.agents/skills/starbase2-evaluate/SKILL.md) | Scenarios, graders, paired comparisons and evidence interpretation |
| [starbase2-world](../.agents/skills/starbase2-world/SKILL.md) | Original scenes, truthful state, progression UI, parity and actual visual QA |
| [starbase2-decision](../.agents/skills/starbase2-decision/SKILL.md) | Consequential architecture tradeoffs and bounded experiments |
| [starbase2-release](../.agents/skills/starbase2-release/SKILL.md) | Proportionate change readiness; separately scoped publication/deployment |

## Predecessor disposition

This is a catalog-level disposition of the 17 Starbase procedures and Lite's
main skill families, with targeted full-text/excerpt inspection of architecture,
documentation, PR readiness, UI, evaluation, add-agent, add-sensor, add-structure,
station-contract, and the Git guard. It is not a behavioral audit of every old
skill. Source revisions are in [research](research.md).

| Existing material | Starbase2 treatment | Reason |
|---|---|---|
| Starbase service-change + contract-change | Rewrite into feature, with conditional boundary checks | Keep ownership/replay/compatibility; remove repeated orientation and handoff lists |
| Starbase evaluation-design | Rewrite into evaluate | Preserve rigor; emphasize per-run results, clustering, equivalence, and tool/model provenance |
| Starbase UI-change | Rewrite into world | Preserve truth/parity; add ambient-life distinction, builds versus characters, and original scene exploration |
| Starbase architecture-decision | Rewrite into decision | Keep genuine alternatives and exit paths; do not force an ADR for routine changes |
| Starbase PR-readiness + release-readiness | Consolidate into release with explicit modes | Avoid duplicate all-surface gates; docs readiness differs from runtime deployment readiness |
| Starbase data-migration | Defer specialist procedure; retain affected checks in feature/release | No Starbase2 deployed data yet; add a tested migration/restore runbook when storage exists |
| Starbase security-review | Retain charter invariants; defer specialized audit skill | Add targeted threat-model procedure when the first candidate/effector boundary is implemented |
| Starbase performance-evidence | Integrate affected baseline checks; defer standalone specialization | No claim that Rust or a graph improves performance without a measurement |
| Starbase incident-response + Kubani-operation | Defer until a real installation and tested runbooks exist | Kubani remains the authority for its own operations; no copied operational commands |
| Starbase repository-triage | Rebuild later as a runtime capability | Product crew work is different from development assistance |
| Starbase debt-cleanup | Fold scoped cleanup into feature; defer a standalone audit skill | Keep owner/removal conditions without loading a second checklist for a small refactor |
| Starbase verify-documentation | Shared charter and automated docs checks; decision for material semantic changes | Avoid requiring a long skill for each typo or link correction |
| Lite add-agent-class | Replace with agent | No mandatory class-per-role, skill-per-class, twin preset copies, or kernel-edit prohibition |
| Lite add-sensor | Replace with feature's connector path | Reevaluate sensor language and routing; preserve fixtures, checkpoints and freshness |
| Lite add-structure + add-crew-member | Replace with world | No inherited map coordinates, scene filenames, or character-to-class identity contract |
| Lite station-contract | Feature + world at the seam | Use versioned schemas and mixed-version tests; do not impose synchronized deployments with no compatibility window |
| Lite Python style / uv / unit-testing | Tool configuration and concise owner docs | Machines enforce formatting and typing; skills need not duplicate ordinary language tutorials |
| Lite Godot implementation guides | Rebuild focused references after visual spike | Geometry, renderer, asset pipeline, and export priority are not settled |
| Lite vendored PydanticAI/Temporal manuals | Prefer pinned official docs and selected references | Avoid a large stale manual embedded in every agent's context |
| Lite secure-practices and pre-git guard | Redesign feedback hooks; keep CI/server enforcement | A command-string matcher and optional local scanner are not a security boundary |

## Rules deliberately dropped from the new skill design

- Fixed total source-line ceilings or a 40-line class budget. Review complexity
  through ownership, dependencies, change comprehension, and evidence.
- A minimum request allowance of 32 for a subscriber. Set maximum resource budgets
  from the task and permit successful early stopping.
- Mandatory live-model preflight for every PR, including schema/UI-only work.
  Apply model evaluations to behavior claims and relevant changes.
- Universal "never add a fallback" rules. Compatibility and degraded behavior
  should be explicit and tested, with owned removal conditions.
- Repeated instructions to read every standard or invoke many skills before
  ordinary work. Load one coordinating skill and only the affected specialist.
- Duplicated local/cloud YAML or model-specific literals as universal templates.
  Resolve a build's effective configuration and record it once.
- Treating development skill presence as permission or as an installed runtime
  capability. These are different trust and lifecycle domains.

"Dropped" means not introduced into Starbase2. No skill or hook in Starbase,
Starbase-lite, the user's global configuration, or Kubani was deleted or changed.

## Discovery, plugins, and hooks

Canonical source lives in `.agents/skills`. Claude's `.claude/skills` entries
link to those same folders, keeping repository-local procedures consistent.
Test discovery in both actual applications during the walking skeleton; file
validation alone does not prove a host loaded the skill.

Distributable Codex and Claude plugins are deferred until reuse outside this
checkout is useful. Packaging must include portable references and validate
each host manifest/hook schema. Do not ship repository-relative links in a
standalone plugin and assume they resolve in its installation directory.

No predecessor hooks are enabled. Introduce versioned hook adapters only after
their shared check scripts exist. Hooks supply fast feedback; mandatory checks
also run in CI, and production authority remains enforced at the server/tool
boundary. Missing hooks cannot silently weaken policy.

## Skill validation and iteration

Validate names/frontmatter, local reference paths, and symlink targets. Review
the following routing and behavior cases as each skill evolves:

| Request | Expected handling |
|---|---|
| Fix a broken documentation link | Direct edit and docs check; no live eval or deployment gate |
| Add a Rust Kubernetes observation adapter | feature; fixture, checkpoint, freshness and bounded-scope tests |
| Change a review agent's tool and prompt | agent; new build and relevant evaluation, no automatic privilege |
| Decide whether a 2% observed quality delta is real | evaluate; inspect sample design/intervals and allow inconclusive |
| Make idle NPCs play chess | world; decorative routine, no fabricated real agent dialogue or model loop |
| Render a verified repair celebration | world; event mapping, no premature success on tool acceptance |
| Replace PostgreSQL with a graph store | decision; compare evidence, ownership, migration and exit cost |
| Review a documentation-only PR | release's repository mode; no model endpoint or cluster access required |
| Deploy an approved digest to a named environment | release; reuse existing authorization, verify exact plan and actual outcome |

Validation on 2026-09-05: the skill-creator validator passed all six skills;
all six UI metadata files parsed; all six Claude links resolved to the canonical
folders; repository documentation link/status checks passed. The routing cases
above received self-review, not automated routing or independent agent forward
tests. Host discovery and behavioral effectiveness remain to be exercised.

Collect real misroutes, unnecessary steps, missing evidence,
and context cost. Narrow or merge a skill when evidence shows overlap; remove
one when it no longer supports a recurring workflow. Owner: Al. Review after the
first end-to-end slice and after material architecture changes.
