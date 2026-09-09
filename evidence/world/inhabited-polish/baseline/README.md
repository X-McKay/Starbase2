# Inhabited polish baseline and acceptance

`source-hashes.json` records a pre-edit snapshot without copying large assets. The 525 world files exactly matched the previously qualified living-colony final-03 export manifest: no changed, missing or added files. All 221 inputs listed by the preceding production provenance also matched; 150 relevant production files received a separate current hash snapshot.

Visual baseline reviewed: `evidence/world/living-colony/final/package-03/habitat-interior.png` and `living-colony.png`. Habitat has sparse pod/chair/sofa furnishings and a plain interior floor; the overview has conspicuously repeated river wave shapes. These are observations, not acceptance substitutes.

## Bounded acceptance

- Run the new `test_inhabited_journey.gd` once after coordinated import: live operator run, stop and orthogonal turn; no frame displacement above 6 m/s; physical plateau-to-spring-to-Habitat travel; water destination rejection and physical shore contact; both water clocks advance normally and freeze under reduced motion; Habitat console access, actual authored camera, E/Escape guide and equivalent direct visit; no dispatch.
- Run the character agent's `test_inhabited_character.gd` for secondary-motion, actual contacts, terrain-aware footfalls and default/immediate mute. Run existing `test_remaining_structures.gd` for declared furniture physical contacts and sidewalls.
- Run the new journey natively with optional `--output=<absolute directory>` to retain actual presentation frames and `inhabited-journey.json`: moving operator, stopped plateau, spring normal/reduced, Habitat exterior/interior/guide. World processing and camera remain enabled; no capture-only camera override. Inspect image quality and movement evidence rather than treating clocks as proof of attractive water.
- After representative review and subsequent room changes settle, root coordinates one affected world/repository suite and standalone export qualification against frozen, hashed sources. Preserve failures and diagnose before rerunning.

Focused command: `mise exec -- godot --headless --path apps/world --fixed-fps 60 --script test_inhabited_journey.gd`. Native command omits `--headless` and appends `-- --output=<absolute-directory>`. No full-suite run was performed while assets were changing.
