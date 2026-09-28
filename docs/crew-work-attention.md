# Grounded crew work attention

Status: proposed

The implemented rendering slice adds restrained, role-specific head attention to
crew already performing the authored handheld Equipment pose. Mender uses short
checks, Surveyor lingers over the slate, Trainer scans more often, and Watchkeeper
holds a slower watch. These are cosmetic mannerisms, not classifications of model
thought, task progress, successful reasoning, or artifact delivery.

## Authoritative journey

The existing `crew_presentation.gd` projection selects `console` only for a fresh
working record (`running`, `executing`, `analyzing`, `evaluating`, or `verifying`).
`crew_motion.gd` exposes the pose after physical workstation arrival. The new
`characters/work_attention.gd` applies only while that authored work clip is
active, movement is stopped, and reduced motion is off. Queued, cancelled,
unknown, stale and disconnected work cannot produce the overlay. Suppression
clears its local phase; reentry eases in over 0.8 seconds. Nothing waits for this
animation or dispatches because it occurred.

Crew roles retain different bounded scan intervals (10–16 seconds), phase and
small nod/glance ranges. Rotation is composed through the imported parent joint
orientation, rather than assuming all rigs share head-local axes. Only the Head
rotation changes: Equipment grips, arm animation, root, hips and feet retain the
authored channels. Hair remains a descendant of the head and retains its existing
secondary motion. This supplements the existing full-body authored animation;
it does not deliver the entire proposed animation catalog.

The Crew/Work structured views remain the source for exact status, timestamps,
evidence and controls. This adds no control, sound, dense marker, backend field,
progress indicator, success celebration or permission. Reduced motion restores
the existing still-pose behavior. No new data or API contract is required.

## Verification and limits

Focused checks cover five selected crew rigs, after-engine-frame persistence,
unchanged hands/hips/feet, bounded offsets, suppression and fresh/stale/queued/
cancellation projection. Separate existing slate attachment, motion-continuity,
and physical crew-route regressions are run in the associated evidence record.
Native paired captures compare the same authored sample with the overlay off/on
for Mender, Surveyor and Watchkeeper; reduced-motion captures retain the still
pose. This is a restrained animation polish pass, not a performance improvement
claim or qualification of new rigs.

See [local review evidence](../evidence/world/crew-attention-20260927/README.md).
Integrated world verification belongs to the parent implementation pass. Native
standalone export, production operation, human accessibility and owner art
acceptance are not established here. Artifact handoff animation remains owned by
the joint-operation projection work and requires real dependency records before
it can truthfully appear in the world.

Rebuild with the existing pinned Godot import/run commands. Rollback removes the
head-attention helper integration and its source; it requires no data migration.
