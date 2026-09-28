# Asset production

Editable production files live here. Godot loads finished resources from
[world assets](../apps/world/assets/README.md). Both use the categories and asset
IDs defined in the [content taxonomy](../docs/content-organization.md).

The active [Meshy world-expansion allowance](batches/meshy-world-expansion/README.md)
is 1,500 credits, authorized on 2026-09-10. The
[Morning slice](batches/morning-at-starbase2/README.md) uses 30 actual credits and
the [selected cast](batches/new-cast/README.md) uses 210. Total: 240 spent,
zero pending, and 1,260 remaining, separate from historical batches.

| Category / asset | Purpose | Rebuild |
|---|---|---|
| `characters/wayfinder`, `rivet`, `moss-cartographer`, `stillpoint`, `night-shift`, `prism` | Six selected independent cast bodies, own rigs, hair and work/rest animation | [Batch recipe](batches/new-cast/scripts/README.md) |
| `characters/captain`, `characters/eva` | Illustrated captain inputs and retained technical pilots | `mise exec -- just characters-import`; pilot render uses Blender 4.5.3 |
| `structures/engineering` | Selected shell and furnished interior | `mise exec -- just world-engineering-build` |
| `structures/command`, `training`, `habitat`, `botanical` | Selected authored frontier structures | `mise exec -- just world-remaining-build` |
| `props/mission-table`, `communications-array`, `simulation-station`, `frontier-galley`, `hydroponic-rack` | Generated equipment for remaining structures | `mise exec -- just world-remaining-build` |
| `structures/engineering-prototype` | Earlier generated structure retained for supported references/recipes | [Original batch](batches/meshy-blender/provenance.json) |
| `props/containment-reactor` | Selected Engineering reactor | `mise exec -- just world-engineering-build` |
| `props/reactor-apparatus` | Earlier reactor used by colony build and previews | [Original batch](batches/meshy-blender/provenance.json) |
| `props/habitat-lounge-sofa` | Selected sage Habitat sofa | `mise exec -- just world-inhabited-build` |
| `environment/aster-vegetation` | Closed curved exterior groundcover, four shared runtime batches | [Pinned Blender recipe](environment/aster-vegetation/README.md) |
| `environment/living-commons` | Authored garden and dimensional leaves | [Commons recipe](environment/living-commons/README.md) |
| `environment/colony-vent` | Authored decorative wall fan | `mise exec -- just world-inhabited-build` |
| `kits/aster-domestic` | Habitat lounge and Commons furniture, textiles and domestic detail | [Blender recipe and provenance](kits/aster-domestic/README.md) |
| `props/field-slate`, `props/daybook` | Handheld work equipment and physical historical briefing instrument | [Morning production](batches/morning-at-starbase2/README.md) |
| `environment/morning-atmosphere` | Doorway textiles, Habitat wall detail and suspended planters | [Blender source](environment/morning-atmosphere/README.md) |

The Shift Change implementation reuses the selected Meshy characters and props,
with a new [generated composition target](batches/shift-change/concepts/art-target-v1.md),
editable domestic dressing and rig-specific social animation. No new Meshy
credits are spent in this pass. [Physical evidence](../evidence/shift-change/physical/README.md)
records home reservations and actual round trips for all five crew; native
animation and final artifact qualification are recorded separately.

The current [inhabited-polish pass](batches/inhabited-polish/DESIGN.md) adds the
selected sofa, four-room interior detail, authored fans, water motion and
upper-hair/surface-footfall presentation. Its offline `world-inhabited-build`
recipe preserves original inputs. The separate new 1,000-credit allowance has
39 actual Meshy credits spent, zero pending, and 961 remaining; historical
507-credit generation is excluded. Three final focused tests, `just check-world`
and `just check` passed. Native four-room images were inspected; standalone
qualification passed in `20260908-final-01`, matching all 553 frozen world files.
The [durable manifest](../evidence/world/inhabited-polish/final/package-01/manifest.json)
binds the unsigned macOS package and retained exported images. Owner art
acceptance and human audio audition remain open.

The preceding [living-colony frontend pass](batches/living-colony/DESIGN.md) reuses
those generated assets and adds retained interior architecture, distinct material
zones and a shared commons. Its representative Command slice and corrected
world/repository checks passed; fresh export qualification passed in `20260907-final-03`. Use
the `world-living-build` recipe for that composition. No new Meshy spend
is part of this pass.

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

Historical remaining-structures qualification: the unsigned macOS `20260907-final-02` review passed, with
exact source/artifact hashes in its manifest and an inspected nonblank 12-frame
motion contact sheet. Full world checks preceded the capture-only RGB8 fix;
the fresh standalone run covers that final capture change. This establishes
local technical qualification, not owner art approval or deployment readiness.

The [Habitat accents kit](kits/habitat-accents/README.md) adds editable Blender domestic dressing for the `inhabited station refinement` (local review evidence is retained outside this commit), with zero additional Meshy spend.
