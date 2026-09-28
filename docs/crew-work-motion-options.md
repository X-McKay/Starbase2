# Crew Equipment handling: motion review options

Status: accepted

Owner: world implementation; Commander owns art-direction sign-off. Local review
2026-09-27. Commander selected **A · Precise** on 2026-09-27. This implements a Rivet vertical slice and two reversible motion
treatments; it does not claim that every crew member has a finished action set.

## The visible change

The native baseline shows empty hands at 0.13 seconds and a fully raised slate
at 0.23 seconds. Work sampling also began at whatever phase the unrelated idle
clock happened to reach. The first correction gives work a dedicated entry clock,
a controlled reach blend, and a settled interval before head attention.

Rivet now has a persistent magnetic side dock. The left hand reaches its actual
grip, picks up the existing slate, lifts and rotates it clear of the body, and
brings it into the authored two-hand work pose. When work stops, the left hand
returns the slate to its dock and releases it. Locomotion continues underneath
the arm-only stow; movement, stop controls and backend execution never wait for
choreography. The supporting right hand follows its own reachable pose.

The [authoring source](../apps/world/characters/slate_choreography.gd) uses Rivet's
own selected rig, measured limb lengths, existing idle/work clips and rigid
hand attachment. The narrow mounting rail is local primitive geometry; the
character mesh, skin weights, materials and existing slate asset are preserved.
No Meshy calls, new character generation or cross-rig motion transfer occurred.
The source is editable Godot arm-pose authoring, not a claim of a newly exported
Blender action or a production-qualified asset package.

## Two concrete treatments

| Treatment | Visible pacing | Recommendation |
|---|---|---|
| **A · Precise** | Rivet reaches for 0.30 s, lifts for 0.60 s, then settles into work; stow takes 0.60 s plus a short release. Other crew use a 0.36 s work-entry blend and restrained attention. | Commander-selected default. The complete action reads clearly without keeping an empty supporting hand waiting as long. |
| **B · Deliberate** | Rivet reaches for 0.45 s and lifts for 0.80 s; stow takes 0.80 s. Other crew use a 0.62 s entry and fuller existing head attention. | Useful if slower, more visibly deliberate robot handling is preferred. It changes cosmetic timing only. |

[Front motion preview](../evidence/world/crew-work-cycle-20260927/rivet-front-final.gif)
and [side preview](../evidence/world/crew-work-cycle-20260927/rivet-side-final.gif)
show A on the left and B on the right. Each is a nine-second native sequence:
docked → reach/lift/use → stow while walking → use again → reduced motion.
The GIF previews encode native movie frames at 960×600; the original 1280×800
AVIs remain beside them in the evidence directory.
Walking displacement in these isolated captures drives the rig but does not move
the actor across the stage; actual physical routes are checked separately.

Review the timing preference, readability of grasp and release, mounting-rail
appearance, and any visible body/Equipment clipping. The Commander selected Precise's pacing; that decision does not certify
all-frame skin clearance or the unfinished handling sets of other crew. Independent visual
critique is coordinated by the parent implementation pass.

## Truthful state and interruption

Fresh authoritative working records still supply the existing `console` intent;
actual workstation arrival gates its presentation. Queued, stale, disconnected,
cancelled and unknown work cannot initiate the working action. An interruption
coalesces to stow or release from the current pose, without a backlog of obsolete
actions or an invented success animation. Equipment remaining on a dock is
ordinary appearance, not evidence of work.

Reduced motion immediately places Rivet's Equipment on its dock and suppresses
handling/head animation. Other crew retain their existing still-pose equipment
policy. Exact mission status, evidence and controls remain in the unchanged
structured/keyboard views. There is no new sound, input requirement, backend
field, dispatch call, operational handoff, XP or authority.

Rivet is the only rig admitted to this choreography. Other crew retain their
own existing authored work/Equipment poses and the timing improvements, with no
claim of completed pickup/stow coverage. Their real attachment choreography
requires separate authored contact paths and native review.

## Verification and limits

The [evidence record](../evidence/world/crew-work-cycle-20260927/README.md) retains
the baseline, failed iterations, corrected checks, source hashes and native
review. Tests cover both treatments at 30/60/120 Hz, rigid attachment, actual
transfer contact, repeated entry, moving stow, cancellation, reduced motion and
unchanged root-motion ownership. Existing cast continuity, independent rig,
attention, Equipment attachment and five-crew physical home/work/home journeys
passed in the scoped run. Integrated world and standalone export qualification
remain the parent pass's responsibility.

Bone-contact measurements do not establish all-frame skin intersection freedom.
Front/side native views must remain part of acceptance, and no performance
improvement or production-readiness claim follows from the movie renderer's
encoding statistics. A future source change requires new source-bound evidence.
Rollback removes the Rivet helper integration and restores the previous entry
clock; there is no data migration or external effect to undo.
