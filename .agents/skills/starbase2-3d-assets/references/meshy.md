# Meshy retrieval, generation and credit accounting

Use the bundled client in the [Meshy skill](../../meshy-3d-generation/SKILL.md).
Run its environment check; do not copy its HTTP helpers or print credentials.
Read current endpoint recipes for the operation rather than freezing prices or
API parameters in this skill.

## Retrieve first

Resolve a supplied share link through available browsing tools, then verify the
model title and task ID. Retrieve task metadata through the documented API when
supported. Download the intended engine format (normally GLB in this project),
thumbnail and metadata into the model's project folder. A website label such as
“Meshy 7” does not establish that every public API endpoint supports that model.

Inspect the GLB's animation and skin arrays, not just the viewer pose. Vanguard's
shared source had neither; its walk/run/idle were added later. Some website task
IDs can be read but are rejected by rigging. After a definite rejection, the
returned textured GLB URL may be a supported input; verify the endpoint's format,
orientation and geometry limits before using it. Do not fabricate alternate IDs
or repeatedly try guessed endpoints.

## Plan only the necessary stages

For new assets, a useful path is concept/reference → isolated design image →
mesh → topology/UV preparation → texture → optional rig/animation → Blender.
Choose stages from the inspected asset: remeshing or retexturing an already
suitable source wastes credits and can lose detail. Check required textures and
humanoid pose before rigging. Fetch the animation catalog for real action IDs;
check whether walk/run are already included before purchasing additional clips.

Before a paid dispatch, record the scope, inputs, estimated stage costs, existing
charges, pending reservations and the user's applicable cap. Count previous
batches covered by a total cap; account balance is not spending authorization.
Reuse the user's existing approval. Ask only if the next necessary action would
exceed or materially change it, with the prepared next action made concrete.

The existing [pipeline](../../../../art/engineering-polish/pipeline.py) and its
plan/ledger demonstrate this boundary. A future slice should use its own asset
plan and reviewed inputs, not silently append unrelated work to an old batch.

## Reconcile before retrying

Persist a reservation before POST and the returned task ID immediately. Poll a
known task instead of creating it again. Download completed results promptly;
retention limits can expire. Downloads and metadata reads are not generation.

If submission is uncertain, preserve the reservation and reconcile with provider
state before another POST. A recorded explicit rejection with no created task
can be corrected; a timeout is not proof of rejection. Retain response evidence
without secrets. Count actual charged credits from completed task metadata and
report remaining authorized credits separately from the provider balance.

Use a single writer for the ledger. Parallel independent downloads are possible,
but concurrent generation scripts that overwrite an entire cached ledger can
lose each other's reservations and task IDs. Never retry just because a progress
bar is slow, and do not claim cancellation refunded an already-started effect.
