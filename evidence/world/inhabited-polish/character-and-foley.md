# Character secondary motion and surface contact feedback

The source inspection found one skinned Vanguard mesh with 24 humanoid joints,
four clips, a rigid helmet/face region, and visible loose white hair. There were
no hair or tail joints. The inspected orange mask in
`hair-region-inspection.png` identifies only the upper loose strands; it excludes
the helmet, face and ears. Lower hair was deliberately left in the original rig.

The new `cybercat-vanguard-secondary` variant adds one Head-child `HairSwing`
joint and smoothly transfers 2,080 originally Head-bound vertices. Original
Vanguard source/runtime files remain untouched. `variant-identity.json` verifies
identical POSITION, NORMAL and TEXCOORD_0 accessor bytes and material definitions;
all four clips remain present. The editable Blender source and preparation script
are recorded by the variant provenance.

`secondary-region-audit.json` records 20 sampled poses across four clips: a
0.1-radian bend moved selected strands at most 0.02355 m and moved the other
39,360 exported vertices by 0 m. Runtime projection applies a bounded damped
response to actual displacement and turning; reduced motion or teleport-sized
displacements reset it immediately. The helmet bone matched the original
animation in 90 runtime run/turn samples.

Footfalls still originate from the displacement-driven gait-contact signal.
The commons terrace and Habitat's authored plank strip use a warm wooden impact;
existing paving/interior metal and outdoor soil retain distinct synthesized
impacts. All samples have a ramped onset and remain cached. The existing sound
toggle defaults muted and now stops current foley immediately when disabled.
Six small dust particles appear only on actual soil contacts; stopping, leaving
soil or reduced motion stops emission, and reduced motion hides them immediately.
These are movement feedback, not operational alerts or health indicators.

Focused checks:

- `character-focused.log`: bounded secondary response, teleport/reduced-motion
  reset, original/candidate helmet comparison, three surfaces and distinct audio,
  actual 6 m/s movement/contact cadence, stopping, default mute and immediate mute.
- `run-cadence.log`: existing 6 m/s, 2.8 m stride and stop-to-idle regression.
- `mesh-character.log`: existing detailed-character turn, real wall collision,
  stop-to-idle and reduced-motion regression.

The first focused invocation passed its assertions but reported two audio
shutdown references after a synthetic rapid start/stop. Its log is preserved as
`character-focused-first.log`. Explicit foley teardown and frame-separated audio
testing produced the clean final focused result. No test failure was silently
rerun until green.

Limits: these checks do not replace the parent task's native close-up/movement
review or final package qualification. No perceptual audio audition is claimed.
The prior 96-file preservation claim does not apply unchanged to the newly
authorized `model_visual.gd` and operator resource selection; original character
art inputs remain preserved. No new Meshy calls or credits were used.
