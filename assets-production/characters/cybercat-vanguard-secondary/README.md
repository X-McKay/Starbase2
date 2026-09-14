# Vanguard loose-strand secondary motion

This separate variant preserves the selected Vanguard geometry, material and
walk/run/idle/console clips. POSITION, NORMAL and TEXCOORD_0 accessor bytes match
the original exactly. A new `HairSwing` child of `Head` influences only the
2,080 vertices in the visually inspected upper loose strands. It does not move
the helmet, face, ears, or the complete head. Lower hair retains its original
rig because a safe independent region was not established for it.

The source is the retained, prepared
`assets-production/characters/cybercat-vanguard/blender/vanguard.blend`.
`prepare_vanguard_secondary.py` runs in a separate background Blender 5.2.1
process and writes this variant; it does not overwrite the original source or
runtime. The source-runtime hash gate requires renewed inspection if the input
changes. Ordinary rebuilding makes no API calls and spends no credits.

The smooth selection combines original full Head influence, X below -0.215 m,
and height above 1.43 m. Those values are specific to this inspected model.
Do not reuse them as a general hair-selection algorithm. The colored inspection
image and source identity checks are under `evidence/world/inhabited-polish/`.

A 20-pose Blender audit across all four clips measured zero deformation outside
the selected region and at most 0.02355 m within it for a 0.1-radian bend.
`characters/secondary_motion.gd` responds to actual displacement and turning with
a damped, bounded spring. Reduced motion and teleport-sized displacements reset
it immediately. The original gait and 6 m/s movement remain authoritative.

The variant selection and model projection intentionally change
`characters/definitions/operator.tres` and `characters/model_visual.gd` under this
new milestone's scope; the previous preservation manifest cannot be described as
unchanged for those two files. Original Vanguard GLB/source and Engineering assets
remain separate preserved inputs. Native hair-motion review and focused runtime
checks are required before qualification.
