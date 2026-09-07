# Content taxonomy and retention

Status: accepted

Owner: Al; implementation assistant maintains the taxonomy and migration checks.
Date: 2026-09-07.

The category layout is implemented on `feature/meshy-blender`. The
[migration record](../evidence/world/content-reorganization/README.md) records
moves, cleanup, validation and the pushed baseline. Original paid inputs remain
local rebuild dependencies. See the [initial assessment](../evidence/content-organization/README.md).

## Canonical taxonomy

Use `assets-production/` (plural assets) for production inputs and tooling, and
`apps/world/assets/` for files loaded by Godot. Use the same category and stable
lowercase hyphenated asset ID in both roots. Do not name assets after a tool,
review milestone, crew role or repeated `final-v2` suffix.

| Term / category | Meaning | Boundary |
|---|---|---|
| `structures` | Placed constructions such as Engineering, habitats, masts and platforms | Replaces buildings as the category; exterior and interior are parts of one structure |
| `characters` | Visual character assets, including models, rigs, clips and portraits | Crew is a product identity/role, not an asset category; several crew can use one character asset |
| `props` | Independently reusable objects such as a reactor, console or locker | Structure-specific components can stay with that structure; extract only when independently maintained or reused |
| `kits` | Reusable construction modules or coordinated material sets | A kit is not a miscellaneous bucket for a whole colony or unrelated finished assets |
| `environment` | Terrain, rocks, vegetation, sky and other landscape assets | A placed authored construction belongs in structures, even when decorative |

An **asset** is a maintained reusable visual resource. A **scene** composes assets
and behavior; it is not another asset category. A **room** is an interior or
navigation/inspection context; it is not a synonym for a structure. A **milestone**
is a review/change grouping that may touch many assets, and names evidence rather
than permanent asset directories. UI labels such as Engineering and backend IDs
such as `repair` can differ deliberately; record the mapping rather than renaming
an operational identity during an art cleanup.

## Repository layout

```text
assets-production/
  README.md
  characters/cybercat-vanguard/
    README.md                  status, runtime consumers, rebuild and dependencies
    provenance.json            source IDs, hashes, costs, rights/ownership context
    concepts/                  selected design images and reference material
    originals/                 selected immutable source models and motion inputs
    blender/                   selected editable Blender projects
    scripts/                   asset-specific preparation and export
  structures/engineering/
  props/containment-reactor/
  kits/aster-v1/
  environment/sandstone/
apps/world/
  assets/                      same category and asset ID as production
    characters/cybercat-vanguard/
    structures/engineering/
    props/containment-reactor/
    kits/aster-v1/
    environment/sandstone/
  structures/                  composition, definitions, collision and behavior
  characters/                  definitions and character behavior
  scenes/                      cross-category scene composition
  ...                          other runtime code stays with its existing owner
evidence/world/<milestone>/<review-id>/
.local/asset-work/<category>/<asset-id>/<run-id>/
.local/reviews/<milestone>/<run-id>/
```

Create only folders that have content. `concepts/` includes selected references;
do not create a competing `concept-assets/` or `references/` bucket for the same
purpose. Use `blender/`, not `blender-assets/`, inside each asset. If another editor
is needed, add its named source folder rather than mislabel its files as Blender.
Animations belong in the source project or exported character clips; logic that
selects clips, handles collisions or projects state belongs in runtime code.
There is no production `behaviors/` folder.

`assets/structures/` contains optimized visual resources, while `structures/`
contains Godot scenes and behavior consuming them. This is an intentional
source-of-data versus consumer distinction. There is no second runtime `art/`
directory in the target. Retain Godot `.import` and `.uid` metadata alongside
resources. `.godot/` is regenerable cache. Runtime exports are retained so a
checkout can run without Blender or a paid generation call.

Keep repository checks in `scripts/` and callable recipes in the `justfile`.
Shared Blender/provider preparation belongs in `assets-production/scripts/`;
asset-specific helpers can live under the asset. Multi-asset generation records
belong in `assets-production/batches/<batch-id>/`, a production-only grouping,
not another runtime category. Link those records rather than duplicate ledgers.

## Previous names and migration mapping

| Previous name | Current interpretation |
|---|---|
| `art/`, earlier proposed `asset-production/` | `assets-production/` |
| `apps/world/art/` and `apps/world/buildings/art/` | `apps/world/assets/<category>/<asset-id>/` |
| `apps/world/buildings/`, building catalogs/classes/recipes | `apps/world/structures/`, structure catalog/gallery/test and `world-structure` recipe |
| `art/cybercat-vanguard/` | `assets-production/characters/cybercat-vanguard/` |
| `engineering-polish` | Split by actual contents: Engineering structure, reactor prop, engineer character; it remains an evidence milestone |
| `meshy-blender`, `colony-3d` | Split by actual structure/character identity; neither tool nor colony is an asset category |
| `crew`, operator/Mender/etc. | Preserve product roles; map them to character assets, do not rename backend identities |
| `source/`, `references/` in the earlier draft | `blender/` for Blender sources, `originals/` for unchanged inputs, `concepts/` for design references |
| Existing `evidence/<milestone>/` | Historical paths retained; new world reviews use the target layout |

The [source index](../assets-production/README.md) describes today's files. Historical
documents and measured evidence retain accurate old names and links; add migration
notes rather than globally replacing words inside old records. Preserve product room IDs and historical measurements when renaming runtime
resources. New category names use structures; ordinary descriptive uses of the
word building do not create a separate category.
A missing text-search match is not proof that a dynamically loaded file is unused.

## Original downloads and local state

`meshy_output/` currently contains required paid rebuild inputs and submission/
reconciliation ledgers. It is ignored but **not disposable cache**. The target
`originals/` folder is for selected immutable inputs, not raw provider responses.
Migrating downloads requires updating ledger paths, scripts and hashes together,
plus deciding how large inputs will be retained/restored. Until then, keep their
existing location and record that dependency in the asset README. Selected editable `.blend` sources use Git LFS under
[ADR 0007](adr/0007-versioned-blender-sources.md); paid originals are not added
to Git by default. A source ID or expired URL is not a backup.

Keep credentials, signed URLs and live ledgers out of committed provenance.
`.local/` contains tools and live service state as well as temporary outputs;
only the named asset-work and review paths are scoped to production cleanup.

## Keep, archive, remove

1. **Keep:** selected editable sources, original paid inputs, active runtime
   files, generation plans/provenance, reconciliation ledgers, regression tests,
   and the evidence supporting current claims. Older sprite assets may still
   supply portraits, fallbacks, experiments or tests.
2. **Archive candidate:** superseded source intermediates and review binaries.
   Preserve a verified restorable copy when they are the only reproduction or
   rollback source. Record archive location and hashes before removing originals.
   No external archive has been established by this change.
3. **Removal candidate:** Blender numbered backups after inspecting the selected
   source and confirming no unique recovery work; scratch renders; reproducible
   caches; superseded local package copies after retaining their review manifest,
   useful logs/captures and any needed baseline. A newer filename alone is not
   sufficient evidence.

For evidence, retain the first informative failure and its resolution, the final
check result, representative native images/motion, and exact reviewed artifact
identity. Do not keep every intermediate movie or identical rerun by default.
Do not remove existing linked failures to make a result look cleaner. Age alone
is not a deletion rule; prune once the slice is accepted and dependencies are
checked. A hash proves identity, not that an artifact can be restored.

Before removing runtime files, inspect static and dynamically constructed paths,
Godot resource references, demos, tests and build scripts. Text search alone does
not prove an asset unused. Update affected references and run focused checks,
then world/import and package checks if shipped content changed. Before deleting
local output, check that no running process is using it. Never use `git clean -fdx`
for this repository: ignored files include paid inputs, databases and tokens.

## Inventory and incremental migration

Run `python3 scripts/inventory_content.py > .local/content-inventory.json` from
an initialized checkout with `.local/` present. It reads filenames and sizes,
reports tracked status and retention hints, and performs no cleanup. The report
is local because it includes local state filenames; do not commit it wholesale.
It is not an asset dependency graph or a secret-content scanner.

Migrate a family only when working on it: inventory its inputs/outputs, select
canonical sources, move paths and update recipes/provenance/docs together,
rebuild without generation, and validate native output before retiring the old
copy. Al owns the decision to retire art; the implementing task owns reference
updates and checks. Completion means the documented rebuild and supported
journeys work with the old paths absent. The first migration is recorded in the linked evidence. Future migrations use
the same checks and retain an exact baseline before cleanup.
