# Sleep capsule

Status: generated and prepared; native placement/material review and final unsigned macOS export
qualification passed for local review. Owner art approval remains open. Furnished sleeping unit for the Habitat rear alcoves. This is static decorative equipment, without a rig or
operational authority; animation or physical proximity cannot imply backend work.

Consumer: [habitat](../../structures/habitat/README.md). The selected
editable source is `blender/sleep-capsule.blend`; runtime is
`apps/world/assets/props/sleep-capsule/sleep-capsule.glb`. Preparation preserves imported
orientation and PBR materials, centers the floor origin and uniformly fits the
model inside **3 × 2 × 2.5 m** (width × depth × height). This is a maximum fit box,
not a claim that every measured dimension equals it. Generated geometry is
separate from the consumer's authored collision and interaction markers.

## Rebuild

Run from repository root with Blender 5.2.1:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python assets-production/scripts/prepare_remaining_props.py -- --asset sleep-capsule
python3 assets-production/scripts/connect_remaining_structures.py --asset habitat
mise exec -- godot --headless --path apps/world --editor --import --quit
```

The consumer's architecture must already be built, and its other dependencies
must exist before connection. These habitats make no paid API calls. Preparation
requires the actual downloaded GLB referenced by the complete `sleep-capsule/mesh`
record in ignored `meshy_output/remaining-structures-ledger.json`, plus the
[generation plan](../../batches/remaining-structures/plan.json). Retain those paid
originals and reconciliation records; an expired download link is not a backup.
The inputs are machine-local and are not restored automatically in a fresh clone.

Preparation writes `provenance.json` with source/task identity, actual mesh-stage
charge, applied normalization, geometry/material inventory, and source/runtime
hashes. That stage charge is not the total task spend; image stages and pending
reservations are reconciled in the batch ledger under the new 1,250-credit cap.
The [batch design](../../batches/remaining-structures/DESIGN.md) records the shared
visual and placement contract.

The preparation script overwrites this `.blend` and GLB from the paid input;
it does not preserve manual edits. Save any edited working source separately,
encode accepted changes in preparation or explicitly export the selected meshes
from the edited source as Y-up GLB with PBR materials and no animation, then
update provenance and review the actual consumer. Preserve semantic mesh names,
especially roof-cutaway prefixes. Hydrate `.blend` files with Git LFS before
inspection. Runtime exports can be played without Blender or another paid call.

The completed 13-model batch reconciles to 507 actual Meshy credits, 0 pending
and 743 remaining under its separate 1,250-credit cap. This is the whole batch
total, not this individual asset's cost.

Native inspection must check apparent scale, visible details, texture channels,
cutaway behavior and containment within the authored collision envelope. A valid
GLB import alone does not establish playable or owner-approved art quality.
