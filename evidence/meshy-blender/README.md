# Meshy / Blender evidence

- `world-checks-final.log`: complete world suite and native command fixture pass.
- `test-character.log`: real displacement, stop, facing, collision and reduced motion.
- `preview-controls.log`: skeleton, changing bone poses, reduced motion and keyboard shortcut.
- `head-weight-repair.json`: seven-pose upper-head edge strain before/after repair.
- `engineering-exterior.png`, `engineering-interior.png`, `engineering-inspection.png`:
  native disconnected colony, room and large-text inspector after clearance fixes.
- `head-before.png`, `head-after.png`: native close-ups of the original/repaired
  walk. These captures sample different walk instants; use the JSON for the
  paired deformation comparison, not pixel subtraction of these images.
- `export-check.log`: successful unsigned macOS package test outside the checkout.
  Full artifact, manifest and captures are in `.local/meshy-blender-release/`.
- `validation.json`: compact result, cost and remaining scope.

Initial import/verification logs contain sandbox write restrictions and the
static skinned-AABB assumption that native inspection corrected. The static AABB
is bind-space data and cannot frame this character's posed geometry directly.
`test-rooms-first.log` retains the gantry obstruction. `world-checks.log` retains
the enlarged-pedestal recovery failure; the final pedestal fits the original
navigation grid clearance. Neither failure was dismissed by rerunning unchanged.
`generation.log` retains the second prompt's pre-submission length rejection;
the first known task was resumed and never duplicated. Total generation cost: 60
credits of the approved 80, final balance 3,140.

This is a first art integration and local package check, not an entire roster
migration, a performance improvement measurement or production qualification.
