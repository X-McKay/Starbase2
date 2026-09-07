# Content reorganization — 2026-09-07

Baseline: `3aedbff`, pushed to the existing private `X-McKay/Starbase2` repository
on `feature/meshy-blender` before any moves. Baseline game and repository checks
passed with normal native access. The earlier sandbox-blocked Godot attempt is
retained separately. Git LFS source integrity passed and all source objects were
uploaded before the baseline push completed.

## Changes

[The manifest](moves.json) records 244 file moves. Source content now lives in
`assets-production/`, runtime media in `apps/world/assets/`, and structure code
in `apps/world/structures/`. Category/asset identities match across roots.
Engineering's mixed folder was split into structure, reactor prop and specialist
character sources. Shared preparation scripts and historical multi-asset batch
records have explicit production-only homes. The catalog, gallery, tests and
`world-structure` recipe use structure terminology. Room and crew IDs are intact.

The [taxonomy](../../../docs/content-organization.md),
[production index](../../../assets-production/README.md), runtime index, current
document links and development skills follow the migration. Historical raw logs
and measurements retain their original contents and paths.

[Thirteen numbered Blender recovery copies](removed-backups.json), totaling
404.9 MiB, were removed after selected-source inspection and active rebuilds.
They were different files, not claimed byte duplicates. Current selected sources,
paid originals, ledgers, supported previews/fallbacks and meaningful evidence are
retained. Local tools, service databases and review baselines were not deleted.
Background rebuilds avoid producing new recovery copies and request compressed
Blender saves; no compression ratio or performance improvement is claimed.

## Verification and retained failures

- All 20 selected Blender sources opened with mesh datablocks and no missing
  external images. The first scene-only audit rejected an intentional library;
  the library-aware audit passed. Both logs are retained.
- Colony, Engineering and Vanguard rebuilt from local inputs at the new paths.
  The Vanguard audit retained four clips and 15,565 rigid helmet vertices, with
  maximum measured deformation below 0.001 mm. No paid endpoints were called.
- The 20 selected editable sources retain their exact baseline bytes after
  rebuild verification; [source integrity](source-integrity.json) records both
  selected and regenerated hashes. Reorganization does not require committing
  newly serialized Blender copies when the selected sources already work.
- The [runtime media comparison](runtime-asset-integrity.json) covers 64 files;
  Vanguard is byte-identical. Three authored colony GLBs were regenerated with
  unchanged glTF JSON metadata but differing binary buffers; game/native checks
  cover their resulting behavior and appearance.
- Relocated illustrated sources were imported and pilot atlases repacked from
  retained frames after checking their source hashes. Character checks passed.
- The first full game check found `$Buildings` shorthand still pointing to the
  renamed root node. It is retained in `check-world.log`; the corrected direct
  fixture check and full suite run are separate evidence.

The corrected full game suite passed (`check-world-corrected.log`), including
physical journeys, animation/cadence and native command fencing. Repository
checks passed (`check-repository-final.log`); the first repository attempt found
one long path needing formatter wrapping. Seven export-harness tests passed.

The first standalone interior launch timed out before engine output. Launching
the same archive through macOS Launch Services produced the native view. The
harness now uses fresh Launch Services instances for GUI captures, retains stdout
and stderr separately, and limits timeout cleanup to the exact isolated
executable. This is evidence for the launch-path fix, not a proven OS root cause.
The first failed qualification and diagnostic archive remain in `.local/reviews/`.

The fresh [package manifest](native-package/manifest.json) qualified the unsigned
macOS archive with offline fencing, smoke checks, colony and compact interior
captures. Both views were inspected; the 960×720 room view retains readable
controls, cutaway architecture and characters. The scene still has baseline
crowded distant name labels; this migration makes no new art-acceptance claim.
The manifest binds 371 world files and archive SHA-256
`e7e49f3f87e416c89250e9806b72d306f547b0d73240a17ca1b114830d68f52c`.
The archive is at `.local/reviews/content-reorganization/20260907-launch-services/Starbase2-macOS.zip`.

[Thirty byte-identical unreferenced logs](removed-duplicate-logs.json) were also
removed, with a retained counterpart and hash for each. No unique diagnostic
content was removed. The three changed GLB buffers differ only in measured
floating-point accessor values up to `2.98e-8`; their metadata and integer indices
match the baseline, as recorded in [the comparison](rebuild-float-differences.json).

No backend deployment or generation spend is part of this change.

## Reproduction and recovery

Run `mise exec -- just check-world` and `mise exec -- just check`.
For production sources, install Git LFS and hydrate with `git lfs pull`; the
production index lists rebuild commands and retained local input dependencies.
A standalone review uses `just check-world-export --output` with a fresh local
review directory. A fresh clone can run the committed game but cannot regenerate
paid-source assets without restoring the original ignored downloads/ledgers.

The pushed baseline remains the rollback reference. Revert the migration commit
as a whole if needed, including resource references, source paths and recipes;
do not roll back isolated directories. No data migration or permission changes
are involved. The user authorized a second push only after successful checks.
