# Shift social clips

Blender 5.2.1 imports the exact selected Sentinel, Engineer and secondary-motion
Vanguard runtime GLBs; original geometry, weights, textures and locomotion assets
remain unchanged. Complete editable scenes are retained in `blender/`. Social
animation GLBs contain the exact rig and a tiny skin carrier rather than duplicate
character textures. Godot copies their bone tracks onto the original skeleton.

Rebuild from repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python assets-production/characters/shift-social/scripts/build_social.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python assets-production/characters/shift-social/scripts/audit_social.py
mise exec -- godot --headless --path apps/world --editor --import
mise exec -- godot --headless --path apps/world --fixed-fps 60 --script test_social_animation.gd
```

Enable one named NLA track in an editable scene to inspect its baked action.
Clips: `sit_down` 1.2 seconds, `seated` 3 seconds (stable loop), `stand_up` 1 second.
`actor.presentation_pose` selects `sit` or `stand`; existing facing target selects
chair orientation. Crew motion waits a fixed one-second cosmetic interval matching
the authored `stand_up` duration before departure; it does not poll
`social_transition_finished`.
Reduced motion snaps to stable poses. These poses are cosmetic, with no authority
or simulated operational claims.

The authored chair top is .48 m above the floor, .55 m behind the actor root.
Sentinel uses 1.2 scale and a .76 m pelvis because its thick thigh skin penetrated
the seat at the other rigs' .63 m pelvis. Each rig retains its own original foot
orientation and ankle-to-sole offset. Operator/Engineer removed the old .15 m
visual floor lift. Head-weighted vertices are audited in head-local space through
every baked frame; mixed neck weights are outside that particular assertion.

Per-instance Godot materials retain source maps with metallic 0, roughness .8,
specular .25 and emission disabled. The source maps still contain dark, high
contrast painted details; this is not a new texture set.

Failures and final native contact proof are retained under
`evidence/shift-change/animation/`. The first clip-only test was insufficient:
parent transform accumulation exploded child skin, sparse rest channels retained
prior idle rotations, and bone-only clearances missed Sentinel thigh penetration.
Final side-view native proof and per-rig contact checks replace those claims.
No Meshy calls or credits were used.
