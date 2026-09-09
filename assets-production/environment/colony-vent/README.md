# Colony ventilation unit

Offline authored Blender 5.2.1 asset for the four non-Engineering interiors. An
ivory housing, recessed five-blade graphite rotor, copper hub/rim and narrow
protective bars provide a small, readable mechanical detail. The housing is
1.24 m square. No Meshy requests, textures, sound or collision are added.

- Editable source: [colony-vent.blend](blender/colony-vent.blend).
- Builder: [build_colony_vent.py](../../scripts/build_colony_vent.py).
- Runtime: [colony-vent.glb](../../../apps/world/assets/environment/colony-vent/colony-vent.glb).
- Binding: [colony_vent.gd](../../../apps/world/colony_vent.gd).
- Hashes and tool version: [provenance.json](provenance.json).
- Native evidence: [vent review](../../../evidence/world/inhabited-polish/vent/README.md).

Rebuild in a separate process; this replaces the generated editable source and
runtime GLB, so retain/export any manual edits before rebuilding:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python assets-production/scripts/build_colony_vent.py
```

The imported `Rotor` retains a centered local-Z pivot. Runtime rotation is a slow
constant decorative phase (0.32 radians/second), frozen while reduced motion is
selected or its interior is hidden. It carries no operational meaning. Native
asset inspection and focused behavior checks passed; full-room placement and
package qualification belong to the inhabited-polish integration review.
