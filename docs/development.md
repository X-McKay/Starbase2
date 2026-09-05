# Developer experience

Status: proposed

## One entry point, native tools underneath

Use `mise` for pinned toolchains and `just` for discoverable commands. Use a
Cargo workspace for Rust and a uv workspace for Python. Avoid a custom build
system. Bootstrap should work with a fake model and isolated local services;
a developer should not need Kubani or download a large model to run tests.

| Surface | Proposed tools |
|---|---|
| Rust | Cargo, rustfmt, Clippy, unit/integration tests, dependency and license checks |
| Python | uv, pytest, Ruff formatting/lint, ty type checking, dependency audit |
| Git checks | prek with pinned hook revisions; fast checks only before commit |
| Godot | Pinned engine/export templates, headless state tests, scene import checks, visual review |
| Web console | Small TypeScript application, generated contracts, keyboard/accessibility tests |
| Contracts | OpenAPI/JSON Schema, deterministic generation, cross-language fixtures |
| Integration | Disposable Postgres and Temporal; fake provider/model servers |

[ty](https://docs.astral.sh/ty/) provides Python type checking and editor support;
[prek](https://prek.j178.dev/) runs pre-commit-compatible checks. Resolve and
lock their versions during bootstrap rather than putting floating `uvx` tools
in required checks. Verify the PydanticAI/Temporal combination against those
pins before scaffolding every service.

## Proposed source layout

```text
apps/world/                    Godot client and authored assets
apps/console/                  compact operations view
services/control/              Rust code, migrations, tests, docs
services/evidence/             Rust code, migrations, tests, docs
services/connectors/           Rust adapters, checkpoints, tests, docs
services/runtime/              Python workflows, worker composition, tests
agents/                        build definitions and role-specific skills
evals/                         public scenarios, grader tests, analysis
contracts/                     owner-defined wire schemas and generated clients
deploy/                        reusable product deployment base
tooling/                       small shared checks and plugin packaging
.agents/skills/                canonical development procedures
docs/                          product explanations, decisions, operation
```

Hidden evaluation cases are stored separately from candidate-accessible
checkout paths and mounted only into the verifier. Directory naming alone does
not establish secrecy. Runtime agent skills and development-agent skills have
different authority and release lifecycles; do not auto-load one into the other.

## Command contract

Only `just check` and `python3 scripts/check_docs.py` exist in this initial
design repository. Implement the following with the walking skeleton:

| Planned command | Required behavior |
|---|---|
| `just bootstrap` | Resolve pinned tools, lock dependencies, configure local checks, run doctor |
| `just doctor` | Diagnose tool, port, container, and configuration prerequisites without mutation |
| `just dev` | Start local services and a fake-model world; print URLs and clean up on exit |
| `just fmt` / `just lint` | Native formatters, Ruff, ty, Clippy, schema and boundary checks |
| `just test` | Fast deterministic tests with no external credentials |
| `just test-integration` | Real disposable Postgres/Temporal, duplicate/crash/replay tests |
| `just eval-smoke` | Fake-model and public scenario regression checks |
| `just eval-compare BASE CANDIDATE SUITE` | Validate campaign/budget, run isolated trials, produce a comparison artifact |
| `just bench` | Named repeatable backend, agent-cost, and UI workload profiles |
| `just check` | Full applicable deterministic validation for changed surfaces |

Model-backed evaluation must require an explicit provider profile and budget;
ordinary checks never silently incur inference charges. CI uses the same
commands, with separate fast, integration, model-eval, and release lanes.
No untrusted PR job receives deployment credentials.

## Codex and Claude as development collaborators

Keep `AGENTS.md` short and shared; `CLAUDE.md` imports it. Author workflow skills
once, then package thin tool-specific distributions. Codex discovers repository
skills under `.agents/skills`; both products support plugin packaging, but
their manifests and hook contracts must be validated separately.
[Codex skills](https://learn.chatgpt.com/docs/build-skills),
[Codex plugins](https://learn.chatgpt.com/docs/plugins),
[Claude plugins](https://code.claude.com/docs/en/plugins).

Six original procedures now cover backend features, agent capabilities/tools,
evaluation/scenarios, world changes, architectural decisions, and release
readiness. See the [skill review](skills-review.md) for scope and the explicit
keep/rewrite/defer/drop decisions. Update file and command guidance as real
implementation paths appear; do not copy every predecessor skill into this repo.

Repository-local discovery uses canonical `.agents/skills` and Claude symlinks.
Package portable Starbase2 plugins for each tool when cross-repository reuse is
useful, generated from shared source and checked for drift. Add an optional MCP interface to query
local runs/evidence and request bounded local evaluations only after an actual
consumer benefits. Do not introduce MCP merely to wrap shell commands.

Hooks invoke small shared scripts: expose relevant context at session start,
run affected formatting/checks after edits, and produce an evidence summary at
handoff. Test hook fixtures for both host tools and maintain a supported-version
matrix. Do not assume identical event names or lifecycle semantics. Hooks are
developer feedback, not a security boundary; CI, sandboxing, and server policy
enforce the rules even when hooks are absent.

## Contribution sequence

Select one observable journey, reproduce its failure, implement the smallest
slice, validate it, and update its contract/docs. Agent-behavior changes carry
a build diff and relevant evaluation evidence. UI changes carry actual captures
and state/accessibility checks. Performance claims carry a baseline.

Benchmark bootstrap and common checks in a clean checkout before claiming the
developer experience is seamless. Keep service docs and commands close to their
owner. A new service must pay for its own identity, storage, telemetry, upgrade,
and recovery burden in the ADR that creates it.
