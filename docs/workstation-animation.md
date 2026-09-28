# Crew workstation interaction

Status: proposed

The local implementation is complete for the five selected crew rigs. Combined
world/export qualification and the user's visual acceptance remain separate.
This extends the [crew motion treatment](crew-work-motion-options.md) with actual
environment contact; it does not create new operational phases.

Each arrived crew member prepares their hands, makes restrained alternating key
presses, reads, makes a role-specific display/control gesture, and settles back.
Rivet and Wes use the physical control; Moss compares display sections and Mae
alternates comparison regions. Prism uses the chair control while seated at Command.
The previous standing Prism screen gesture remains documented in baseline evidence.
The display schematic is static dressing. None of these movements reports task
progress, reasoning, a successful action, or an evidence handoff.

The actor supplies an optional station only for fresh working intent after a
physical, stopped arrival. The driver also waits for facing alignment. Movement,
cancellation, stale state and blocked routes immediately clear contact feedback;
contact feedback clears immediately. Seated departure finishes the physical stand
before walking; this never delays backend cancellation. Reduced motion preserves
a valid seated body with neutral, static hands. Handheld equipment is suppressed while station hands are in
use and its existing fallback returns without a station. Unsupported or missing
hand calibration disables this overlay instead of guessing another rig's reach.

`characters/environment_interaction.gd` owns the choreography and own-rig arm
solve. `workstations/interaction_station.gd` supplies world-space contact frames
and accepts measured contact weights. Station placement uses the same visible
floor datum as crew support, while navigation remains planar. Hands prepare over
0.46 seconds with a smooth Cartesian reach; the cosmetic work cycle lasts 8.4
seconds, and return blends over 0.18 seconds standing or 0.32 seconds seated. This keeps the selected Precise
character without the abrupt long-arm entry found in the first pass.

The selected rigs have hand bones but **no finger bones**. Their keyboard and
screen probes come from actual imported skin vertices dominated by the relevant
hand bone: a central distal underside point for keys, the farthest distal point
for the screen. `characters/hand_contact_probes.json` stores these per-side
centimetre-space measurements; `test_hand_contact_probes.gd` audits them against
the selected assets. Screen gestures retain a 3 mm clearance and retract before
rising. This is rigid hand-skin calibration, not independently articulated typing
or a full collision solver for every skinned vertex.

## Seated Command work

Wes and Prism now use the actual Command chairs and large consoles. The canonical
body pose remains `sit`; `seating_station` retains physical furniture context
independently from the fresh `interaction_station` hand binding. Queued, stale,
offline and reduced states keep the seated body without replaying entry.

Arrival first settles the ordinary grounded idle and aligns the body. The authored
sit clip then combines a bounded 0.32 m cosmetic root adjustment with visible
alternating foot steps. `characters/seated_footwork.gd` solves each actual rig
against the visible support surface, measuring stable deformed sole probes.
Hands begin only after the body settles and the chair tray deploys. On departure,
hands withdraw for 0.32 seconds, the tray folds for 0.28 seconds, then the authored
stand finishes before physical travel. The large display is a gaze target; it is
not falsely treated as a reachable touch screen.

The [seated evidence record](../evidence/world/seated-command-animation-20260928/README.md)
separates direct-placed native fit captures from actual-route integration. The
new six-case seated test and nine-case standing test together preserve all five
rigs at 30/60/120 Hz after every engine frame. Seated maxima were 72.69 mm hand
step, 2.35 mm planted sole drift per frame, and 8.85 mm valid contact error. The
actual-route integration additionally checks invalidation, partial-sit reversal,
reconnect, folded tray before walking, and support measured at actual room soles.
The cushion audit uses its exact offset volume; canonical seat reference error
is an alignment metric, not a skin-contact certificate.

## Verification and retained failures

The [native evidence record](../evidence/world/station-interaction-20260928/README.md)
contains the source hashes, all final front/side captures, motion preview, logs,
and the failed iterations. Focused checks completed:

- Prior standing baseline `test_environment_animation.gd`: all five rigs at 30/60/120 Hz, sampled after
  every engine frame; both keys and the role gesture, bounded contact, entry,
  interruption, movement, equipment fallback and static reduced motion passed.
  Worst rigid contact-point step was 75.15 mm at 30 Hz, 37.69 mm at 60 Hz and
  18.88 mm at 120 Hz, below the unchanged 80 mm continuity gate.
- `test_hand_contact_probes.gd`: saved probes match actual selected skin geometry.
- Native final captures: all five rigs in matched front/side views, entry, keys,
  display/control gesture, return and reduced motion. An independent critic
  confirmed the corrected screen clearance and credible keyboard placement.
- `test_environment_interactions.gd` (integration owner): real snapshot projection,
  physical routes, both keys for all five crew, invalidation gates and return home
  passed after correcting the actual room-floor datum. No command was dispatched.

Initial 0.5 m controls exceeded several arm lengths. Initial screen targets
crossed the reach envelope and caused arm resets; reachable display regions and
clamped own-length solving corrected this. An assumed palm offset let rigid
fingers penetrate the monitor: skin calibration corrected that visible defect.
The first capture helper reused a camera frame; waiting for the camera/layout
update before readback produced distinct front/side evidence. A 0.36 second
entry then exceeded the unchanged continuity gate for the longer hands; the
0.46 second preparation and eased read-to-key transition passed at every rate.
Failures remain in the evidence, including the temporary inferred-type compile
error; none is counted as a passing qualification.

No frame-rate improvement is claimed. A future finger-rig enhancement belongs to
character asset production: completion requires separately deforming digits,
native key/screen contact without penetration, all-cast regression and user visual
acceptance. Until then, describe these actions as rigid-hand workstation gestures.
Rollback removes station binding and restores the existing field-slate fallback;
no operational record or permission needs migration.
