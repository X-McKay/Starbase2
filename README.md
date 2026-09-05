# Starbase2

A living research outpost whose crew does real work, proves its improvements,
and earns its reputation.

Starbase2 reimagines [Starbase-lite](https://github.com/X-McKay/Starbase-lite)
and [Starbase](https://github.com/X-McKay/Starbase) for deployment on
[Kubani](https://github.com/X-McKay/kubani): Python agents and Temporal
workflows, a predominantly Rust backend, and an original Godot 2.5D world.

**Status: design foundation.** This repository contains the initial proposal,
research, engineering charter, six original development skills, and documentation checks. It does not yet
contain a running agent system, game client, or deployment.

## Start here

- [Product proposal](SPEC.md): the world, agent system, and acceptance criteria.
- [Architecture](docs/architecture.md): four initial services and their boundaries.
- [Agent evaluations](docs/evaluations.md): how to distinguish improvement from noise.
- [World and RPG design](docs/experience.md): crew, equipment, progression, and the gym.
- [Development workflow](docs/development.md): Rust/Python tooling and Codex/Claude integration.
- [Skills review and new catalog](docs/skills-review.md): six original procedures and what was dropped or deferred.
- [Delivery plan](docs/roadmap.md): a playable first slice, then continuous duties and improvement.
- [Research and evidence](docs/research.md): inspected revisions, findings, and limitations.
- [Proposed foundation decision](docs/adr/0001-starbase2-foundation.md).

## Check this repository

With Python 3.11 or newer:

```sh
python3 scripts/check_docs.py
```

If `just` is installed, `just check` runs the same check. Planned application
commands are explicitly marked as planned in the development document.

The previous repositories and their running installations remain independent.
No old workflows, data, permissions, or deployments are implicitly migrated.
