# Asset production

Editable production files live here. Godot loads finished resources from
[world assets](../apps/world/assets/README.md). Both use the categories and asset
IDs defined in the [content taxonomy](../docs/content-organization.md).

| Category / asset | Purpose | Rebuild |
|---|---|---|
| `characters/cybercat-vanguard` | Selected player, rig and four clips | `mise exec -- just world-vanguard-build` |
| `characters/engineering-specialist` | Mender's Engineering suit | `mise exec -- just world-engineering-build` |
| `characters/cybercat-sentinel` | Earlier repaired crew, still used by other roles | Shared preparation scripts; see [production record](../docs/meshy-blender.md) |
| `characters/captain`, `characters/eva` | Illustrated captain inputs and retained technical pilots | `mise exec -- just characters-import`; pilot render uses Blender 4.5.3 |
| `structures/engineering` | Selected shell and furnished interior | `mise exec -- just world-engineering-build` |
| `structures/command`, `training`, `habitat`, `botanical` | Selected authored frontier structures | `mise exec -- just world-remaining-build` |
| `props/mission-table`, `communications-array`, `simulation-station`, `frontier-galley`, `hydroponic-rack` | Generated equipment for remaining structures | `mise exec -- just world-remaining-build` |
| `structures/engineering-prototype` | Earlier generated structure retained for supported references/recipes | [Original batch](batches/meshy-blender/provenance.json) |
| `props/containment-reactor` | Selected Engineering reactor | `mise exec -- just world-engineering-build` |
| `props/reactor-apparatus` | Earlier reactor used by colony build and previews | [Original batch](batches/meshy-blender/provenance.json) |

The [remaining-structures batch](batches/remaining-structures/DESIGN.md) uses
built-in imagegen concept plates, Meshy-generated hulls/equipment and Blender
preparation. Four larger rooms preserve `review`, `gym`, `habitat` and
`greenhouse` identities; Engineering and current characters remain preserved.
Nine equipment assets use `props/` with per-asset READMEs and preparation records.
The completed 13-model batch records 507 actual Meshy credits, 0 pending and 743
remaining under its separate 1,250-credit cap. Full world and repository checks passed and the final unsigned macOS export
qualified. Owner art review remains open. Production assets alone do not establish acceptance.

`blender/` holds editable projects; `concepts/` holds selected design references.
Directly authored SVGs and generated raster assets without separate editable
sources remain in runtime assets; do not duplicate them to fill this directory.
The canonical source for the older raster kit is its runtime image and provenance.

[Shared preparation scripts](scripts/) operate on multiple assets. `batches/`
retains historical multi-asset prompts, plans, reviews and cost/provenance records;
it is not a runtime asset category. New per-asset provenance should link shared
batch records instead of copying a ledger. `structures/colony-layout.json` is
shared composition data; its keys preserve the existing room identifiers.

Paid originals and task ledgers remain in ignored `meshy_output/`. They are
required for the Meshy-derived rebuild recipes; source retrieval is not a new
paid generation. This migration does not move or publish these ledgers. Blender
sources use Git LFS: run `git lfs install --local` and `git lfs pull` after cloning
if you need editable sources or the full world suite, which verifies pilot source
hashes. Playing and exporting the game use the committed runtime exports.

Blender 5.2.1 is used for the native colony/rig pipelines. Background source saves
are compressed and do not accumulate numbered backups. The earlier captain/EVA
render pipeline remains pinned to Blender 4.5.3.

Final qualification: the unsigned macOS `20260907-final-02` review passed, with
exact source/artifact hashes in its manifest and an inspected nonblank 12-frame
motion contact sheet. Full world checks preceded the capture-only RGB8 fix;
the fresh standalone run covers that final capture change. This establishes
local technical qualification, not owner art approval or deployment readiness.
