# Content organization assessment — 2026-09-07

Read-only inventory before migration. See the [taxonomy](../../docs/content-organization.md)
for canonical names and the target layout. No assets were moved or deleted.

Logical sizes from `scripts/inventory_content.py`, before documentation edits:

| Root | Files | MiB |
|---|---:|---:|
| `art` | 69 | 925.0 |
| `apps/world/art` | 127 | 217.8 |
| `apps/world/buildings/art` | 13 | 14.7 |
| `evidence` | 1083 | 214.6 |
| `meshy_output` | 60 | 560.8 |
| `.local` | 39935 | 5477.7 |

Thirteen numbered Blender backups total approximately 404.9 MiB. These are review
candidates, not proven duplicates. The original inventory is local at
`.local/content-inventory.json`; regenerate it rather than treating counts as
current. It records names/sizes/tracked status, not content or dependency closure.

Current source directories mix structures, props and characters. Runtime uses
both `art/` and `buildings/art/`; structure code uses `buildings`. Crew roles and
room IDs have meaningful product semantics and must not be mechanically renamed.
The canonical guide defines these distinctions and maps old names to targets.

Migration remains deferred. Start with Engineering's actual dependencies, update
scripts/resources/docs together, rebuild without paid calls, and qualify the
changed game before retiring old paths. Al owns art retirement; the implementing
task owns migration and checks. Original paid inputs and live local state remain
protected from blanket cache cleanup.
