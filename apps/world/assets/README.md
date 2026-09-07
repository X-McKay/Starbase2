# Runtime assets

These are the optimized resources loaded by Godot. Editable sources, selected
concepts and preparation tools live in [asset production](../../../assets-production/README.md).
Use the same category and asset ID in both places; see the
[content taxonomy](../../../docs/content-organization.md).

- `characters/`: Vanguard player, Engineering specialist, Sentinel crew,
  captain/EVA pilots, and the shared frontier crew portraits/fallbacks.
- `structures/`: Engineering, Command, Training, Habitat, Botanical and the
  retained Engineering prototype. Illustrated structure art remains available
  to supported definitions and previews.
- `props/`: containment reactor and earlier reactor apparatus.
- `kits/`: Aster material atlas and original frontier surface SVGs.
- `environment/`: sandstone geology and original plant/tree SVGs.

Scenes, collision and behavior live in `../structures/`, `../characters/` and
`../scenes/`. They consume these assets rather than duplicating them. Keep `.import`
sidecars and `.uid` metadata; `.godot/` is generated cache. Runtime exports are
committed so playing the game needs neither Blender nor generation credits.

Original Starbase2 artwork and generated-asset provenance are retained with the
asset or linked production batch. Historical measurements remain in evidence;
asset relocation does not make a new performance or visual-quality claim.
