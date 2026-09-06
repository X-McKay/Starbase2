# Command District and repository watches

Status: accepted

Implemented behavior, with the art limitation below.

Open **Command board [B]** from anywhere, or use **E** at Survey Command's
interior console. The board presents observations, watched repositories, memory
proposals and evidence. **Findings** loads the full retained record separately;
source/revisions are one further selection. Start and Stop remain explicit
operator actions. Travel, footsteps, dust and door sounds are decorative.
The browser journal has equivalent observation, watch and memory controls.

## Repository management

Add `owner/repository` under **Repositories** (native) or **Watched repositories**
(browser). Names normalize to lowercase. Set a 30–86400 second interval; the first
automatic check follows that interval after worker registration. Once registered,
the native target selector or browser **Observe now** can request an immediate
observation. At most 20 repositories can be retained as non-removed watches.

Pause prevents future dispatch. Remove also hides the active watch in the browser
and retains its configuration tombstone, run evidence and memory. Restore reuses
its identity with a new generation. Already queued/running observations continue
until explicitly stopped. The list distinguishes watch configuration from latest
observed state/time and marks overdue observations stale. Existing file-configured
individual-PR duties remain separate: the native list identifies them, and the
browser's recurring-duty controls manage them. Removing a repository watch does
not silently remove another independently configured duty.

The Rust core owns `/v4/repositories` and `repository_watches`. Edits require the
next generation; exact retries are idempotent and stale concurrent edits fail.
The Python worker derives immutable builds from core-owned watches and reuses
`FieldDutyV4` and `FieldObservationV4`. No new service, workflow type or datastore
was added. Pausing/removal is checked by the core immediately before dispatch.
A lost native write response triggers record reconciliation, not another write.

Only fixed-origin GitHub GETs are used. Public repositories require no token.
Private access must already be bound to the exact repository through a
`token_file` in operator-owned `STARBASE_FIELD_TARGETS_FILE`; ambiguous bindings
fail. The UI accepts no credential, arbitrary URL, shell command or model prompt.
These watches never request inference or publish GitHub reviews.

Each observation lists up to 11 open PR identities and reviews at most the 10 most
recently updated. An eleventh produces an explicit coverage exclusion. Each PR is
limited to 10 Python blobs and 80 KB of source; the complete repository capture
has a 90-second deadline. The existing Git-blob verification, changed-line checks,
head/base drift rejection, total finding cap and source masking remain in effect.
An empty open-PR list is a recorded observation, not a repository certification.
Checks currently repeat within that window; they do not guarantee coverage of
older PRs, perform incremental ETag caching, or review every language. Coverage
limits and failures must remain visible before increasing scope or frequency.

## World and development workflow

Shared building hosts now add a soft footprint shadow and a physical doorway
sill, independent of collision and artwork. Movement produces small soil dust
puffs; paved/interior footsteps and soil footsteps use different original
synthesized sounds. Quiet airlock feedback plays on entry/exit. Enable sound in
**H / Settings**; it defaults off. Reduced motion suppresses dust. The footer now
has a translucent backing for legibility against detailed terrain.

```sh
just world-command       # native Command room and board; existing dev core
just test-repositories   # actual Core/Temporal/FalkorDB; synthetic GitHub HTTP
just check
just check-world
```

The explicit `capture_command_journey.gd` QA scene records walking, entrance,
console approach and evidence inspection with fixture-only commands disabled.
Its capture arguments and retained results are in the
[evidence index](../evidence/command-district/README.md). This makes motion review
repeatable without turning a demo into agent execution.

Two image-generated captain walk sheets failed review: both had a baked
checkerboard without usable alpha and inconsistent stride/cell alignment.
Neither is loaded by the world. Existing four-direction artwork and decorative
bobbing remain. The art owner’s next completion gate is a cleaned, pivot-aligned
four-direction walk cycle, reviewed in motion at normal and compact scale before
replacing the shared crew atlas. A passing code check cannot approve that asset.
No new animation-quality or rendering-performance improvement is claimed.

## Migration and activation

SQLite becomes V5; PostgreSQL receives additive V3 after unchanged V1/V2
checksums. The deployment renderer records the new schema hash; runtime grants
allow watch INSERT/UPDATE/SELECT, not deletion. Run the migration job and grants
before the new image starts. Rollback uses a schema-compatible image or the
existing restore-into-empty-database playbook, not a destructive down migration.
Local PostgreSQL tests and the owned deployment/backup/restore/teardown rehearsal
passed. No Kubani resources were changed; production field/memory activation
and Linux-host sandbox qualification remain separately gated.
