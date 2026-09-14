# Starbase2

A living planetary colony whose crew does real work, proves its improvements,
and earns its reputation.

Starbase2 reimagines [Starbase-lite](https://github.com/X-McKay/Starbase-lite)
and [Starbase](https://github.com/X-McKay/Starbase) for deployment on
[Kubani](https://github.com/X-McKay/kubani): Python agents and Temporal
workflows, a predominantly Rust backend, and an original Godot 2.5D world.

Explore the [planetary colony](docs/world-colony.md) with `just world`; press M
for the colony map or use `just world-map`.

The [approved art kit is now in the playable colony](docs/world-rollout.md).
Press F near a main entrance to visit its interior, E at its console to inspect,
and F to return. Inspectors also offer **Visit this room**. `just world-kit`
retains the isolated art showroom for future asset review.

**Status: functional Godot-native operations edition.** Review Python files without
executing them, run paired evaluations, schedule durable recurring reviews, and
inspect retained source citations and history in the native Godot outpost. The
Core root page is a non-interactive service surface. A disposable `starbase2-prod`
Kubani pilot has been rehearsed with bounded duties and read-only provider
scopes; durable production admission and external writes remain separately gated.
The [repair workshop](docs/repairs.md) now runs model-proposed fixes in pinned
microsandbox VMs, retains independent judgments and diffs, and awards duplicate-safe
cosmetic XP. See the [sandbox survey](docs/sandbox-survey.md) for the choice.

The [playable Aster outpost](docs/world-playable.md) now has original pixel art,
walking and collision, contextual crew inspectors, native synthetic repair commands,
and evidence-linked trophy displays. The [frontier art pass](docs/world-adventure.md)
adds richer space-adventure crew and architecture. Run `just world`; press H for
controls, or `just world-crew` to inspect the character designs.

```sh
mise install
mise exec -- just bootstrap
mise exec -- just dev
# In another terminal:
mise exec -- just world
```

Launch Godot with `just world` and press `J` for native operations. See the
[implemented workflows and limits](docs/operations.md), [current refactor
handoff](docs/recent-refactor.md), and [development commands](docs/development.md).

## Start here

- [Product proposal](SPEC.md): the world, agent system, and acceptance criteria.
- [Architecture](docs/architecture.md): the implemented two-part local architecture and deferred production boundaries.
- [Agent evaluations](docs/evaluations.md): how to distinguish improvement from noise.
- [World and RPG design](docs/experience.md): crew, equipment, progression, and the gym.
- [Development workflow](docs/development.md): Rust/Python tooling and Codex/Claude integration.
- [Skills review and new catalog](docs/skills-review.md): six original procedures and what was dropped or deferred.
- [Delivery plan](docs/roadmap.md): a playable first slice, then continuous duties and improvement.
- [Research and evidence](docs/research.md): inspected revisions, findings, and limitations.
- [Proposed foundation decision](docs/adr/0001-starbase2-foundation.md).

## Check this repository

After bootstrap, `just check` runs lint, unit tests, generated-contract checks,
and documentation checks. `just test-integration` exercises real Temporal worker
replacement, duplicate handling, cancellation, replay, and persisted evidence.
`just test-operations` verifies the review/duty product with real Temporal, without inference.
`just check-world` validates Godot import, state, navigation, keyboard interaction,
and local native-command failure fixtures. Documentation-only checks
remain available with `python3 scripts/check_docs.py`.

The previous repositories and their running installations remain independent.
No old workflows, data, permissions, or deployments are implicitly migrated.

## Fresh Kubani deployment preparation

The [setup, rollback, recovery and teardown playbook](docs/deployment.md) covers
the disposable PostgreSQL-backed Kubani pilot and its recovery boundaries.
Durable production admission, provider activation and platform backup
restoration remain required before treating that pilot as a production release.

The [field crew guide](docs/field-agents.md) covers Watchkeeper, GitHub PR Reviewer,
recurring observations, reviewed Graphiti/FalkorDB memory and qualification limits.
Use `just test-field` for the credential-free local end-to-end check.
