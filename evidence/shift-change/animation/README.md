# Social animation qualification

Final selected build is build-06 / import-04. `social-headless-final.log` passes
actual selected rig loading, pelvis and knee clearance, upright torso/head,
per-rig unchanged ankle height against standing, transitions and reduced motion.
`head-audit-final.log` and `head-preservation.json` pass every baked frame's
fully head-weighted skin preservation (head-local displacement under .1 mm).

Native `native-side02/` shows the final Sentinel seated skin contact and planted
toes from the side. `native-after05/` shows all three upright seated rigs before
the final Sentinel-only pelvis elevation. Engineer and Vanguard are unchanged
between those captures. Final integrated warm-world visuals are owned by the
separate domestic journey capture; no integrated qualification is claimed here.
Native logs contain no script or renderer errors. Captures run actual physics
and original skins, with explicit `RenderingServer.force_draw(false)` for each
requested frame, avoiding an indefinite background `frame_post_draw` wait.

Preserved failed/diagnostic attempts:

- rig-inspection.log: sandbox Blender crash; native exact-GLB import used instead.
- rig-inspection-native.log: historical Sentinel blend contained no scene rig.
- build-01: initial IK contact drift; build-02: unreachable arm target assertion.
- native-before: build-03 child transforms accumulated from stale parent evaluation.
- native-after: build-04 bones improved but torso retained unkeyed prior idle channels.
- native-after02/03: resetting rest channels corrected torso; short Sentinel thighs
  still penetrated the slab. Bone-only pose assertions did not prove skin contact.
- native-after04: background capture stalled after standing, no logged errors;
  owned PID72909 stopped after diagnostic sample and unsuccessful one-time AX raise.
- native-side: scaled Sentinel still intersected seat; final rig-specific pelvis
  elevation appears in native-side02. Foot targets remained unchanged.

`final-artifacts.json` records final source/editable/GLB hashes. Large temporary
texture extractions and Blender backups live only under `.local/shift-social-diagnostics`.
Original source GLBs remain untouched. No paid generation calls were made.
