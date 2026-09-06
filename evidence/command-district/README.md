# Command District evidence

Date: 2026-09-06. These are local functional and visual checks, not a production
qualification or an agent-quality comparison.

- `repository-check-final.log`: Rust/Python lint, types, tests, contracts and docs.
- `python-focused.log`: repository scope, bounded synthetic GitHub capture,
  revision drift, changed-line findings and credential-binding tests.
- `integration.log`, `integration.json`: real local Temporal/Core/FalkorDB,
  synthetic provider HTTP. Worker restart, repository observation, removal,
  retained report and workflow replay passed, along with existing field/memory
  recovery checks. `board-fixture.json` contains those synthetic retained records.
- `postgres.log`, `deployment.log`: PostgreSQL tests, additive migration,
  least-privilege runtime, backup/restore, namespace and owned-resource cleanup.
- `world-check-final.log`, `commands.log`: Godot state/layout/interaction checks;
  six native HTTP writes, including lost watch/memory responses reconciled by GET.
- `browser-check.cjs`, `browser-check-final.log`: host-scoped Playwright recipe against
  a fresh local core, no worker. Add/pause/resume/remove/restore, normalized
  identity, revision checks, evidence, memory approve/revoke, offline disabling.
- `repositories.png`, `findings-compact-final.png`, `browser-watches.png`: actual
  native/browser captures, using clearly labeled synthetic records.
- `journey.mp4`, `journey-final.log`, `journey-55.png`, `journey-125.png`,
  `journey-180.png`: recorded native movement/entrance/evidence journey and sampled
  frames. Movie timing is fixed at 30 fps; its render statistics are not a runtime
  performance benchmark. Encoding uses temporary `imageio-ffmpeg==0.6.0`, not a
  shipping application dependency. Godot AVI was not readable by macOS avconvert. The encoded MP4 decodes fully and
  retains a non-silent stereo audio track (`movie-validation.log`); raw AVI is in
  ignored `.local/command-movie/`.
- `rejected-art/`: two built-in ImageGen candidates, rejected for baked background,
  stride and alignment defects. Not imported by the application.

Native capture recipe (run from the project root, with absolute fixture paths):

```sh
godot --path apps/world --script capture_command_journey.gd \
  --write-movie .local/command-journey.avi --fixed-fps 30 -- \
  --fixture="$PWD/evidence/command-district/world-fixture.json" \
  --board-fixture="$PWD/evidence/command-district/board-fixture.json" --compact
```

Earlier check logs are retained: stale schema-version expectations and old
console/directory assertions were updated for the new behavior; the new compact
board test initially used the wrong logical viewport size. The first recording
used an incorrect scene-node name and was corrected to use the building catalog.
No failed capture or check is presented as passing. Credentials, database files
and Temporal histories remain outside these shareable artifacts.
