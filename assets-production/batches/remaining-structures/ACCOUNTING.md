# Generation accounting and input retention

The separate authorized cap is 1,250 Meshy credits, with no historical charges
carried into this batch. All 13 assets completed their image and mesh stages:
26 successful tasks consumed **507 credits**, leaving **743 credits** authorized
and **zero unresolved reservations**. The historical Engineering/Vanguard
milestone is outside this batch's accounting.

The local ledger is `meshy_output/remaining-structures-ledger.json`. Every
downloaded original and task-result JSON referenced by its 26 entries was
present at the audit. Each provider result reported `SUCCEEDED`, and each
`consumed_credits` value matched the ledger. Preserve these inputs: production
rebuilds consume the downloaded GLBs and must not silently regenerate them.
Original result JSON contains provider metadata and remains in ignored local
storage; the public batch snapshot records paths and hashes without copying
provider URLs or credentials.

The generation helper persists a reservation before submission and the returned
task ID before local preparation. A single-writer lock and atomic ledger writes
protect accounting. Unknown submissions block further POSTs; known tasks can
still finish. Concept task IDs gate mesh generation. Fifteen offline tests
cover these boundaries, reference-image routing, and selected hull quality.

After the final Blender rebuild and Godot import, the read-only audit found all
**96** files in `evidence/world/remaining-structures/baseline/preserved-assets.json`
byte-identical to their baseline hashes. All **264** file records in the generated
batch snapshot matched their on-disk hashes, including retained originals,
source files, runtime media, import sidecars and linked provenance. An exact
active-credential scan of the **328** modified/untracked, nonignored output files
then present found no credential matches; signed-provider-URL pattern checks
also found none. These counts describe that snapshot, not subsequent edits.

The generated `provenance.json` reports `locally_complete`: 13 assets, 26 stages,
no unfinished preparation, and no missing artifacts. Rerun `record_provenance.py`
after any asset or import change stops writing. Native/package qualification and
the owner's visual judgment remain separate from generation success and this
accounting record.
