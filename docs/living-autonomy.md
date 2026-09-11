# A miniature autonomous world

Status: accepted. Shift Change presentation is implemented and passed physical and
native offline rehearsals. Final packaged-artifact verification passed;
real-production acceptance below remains open. Owner: implementation assistant;
Al reviews the native experience. Persistent memory remains deferred.

## Implemented experience

Five crew inhabit seven authored Habitat/Commons anchors between assignments.
Shared reservations prevent competing destinations; deterministic dwell timing
varies cosmetic visits. Three anchors support seated poses and four support
standing idle activity. The label **On duty · waiting** describes a fresh enabled
duty, not invented agent reasoning. A paused duty uses the same home behavior
with an explicit paused label when no assignment remains active.

Real V4 field records reach the world through the existing snapshot projection.
Watchkeeper and Reviewer have separate Survey Command workstations. Queued work
interrupts home activity and requests travel. Running work uses the console pose
only after physical arrival. Completion with retained evidence appears immediately
and redirects home; a short job can complete before the actor reaches a station.
Arrival never dispatches, delays or completes backend work. Pausing future duties
does not cancel an already active assignment.

The crew strip and explicit **Watch crew** camera action make inhabitants easier
to find. Watching is an operator choice; assignments never redirect the camera.
Visibility follows the actor's occupied building, including Habitat, rather than
only its assigned workstation. NPC door opening is separate from operator room
cutaway and camera context. A bounded **Route blocked** cue describes navigation
failure alongside unchanged operational state.

Stale/offline state holds motion and clears confident work gestures while retaining
last-known evidence. Reduced motion removes cosmetic travel without teleporting
actors. Reconnect coalesces directly to current intent; concurrent runs keep one
stable crew identity and separate task markers. Keyboard and structured operations
remain available without following an actor through the world.

## Authored places and assets

Habitat remains at world `(36, 0, -15)`. Its lounge sofa moved to local
`(3.4, 0.15, -5.3)` as the central visual focus. Prop origins are distinct from
qualified actor destinations. Four activity markers live in
`structures/interiors/habitat-continuous.tscn`; three more are authored by
`living_commons.gd`, whose shelter is at `(-7, 0, 23)`. Marker metadata includes
identity, pose, zone and facing. Seat geometry, colliders and actor roots remain
aligned; navigation clearance was not weakened to fit the furniture.

`crew_motion.gd` resolves all building visibility, reservations, travel, dwell and
bounded route failures. `crew_presentation.gd` maps authoritative records and fresh
duty state to intent. `characters/model_visual.gd` applies the imported social
clips and per-instance material corrections. Seated departure waits a fixed
one-second cosmetic interval matching the authored stand-up clip; no backend work
waits for that animation.

These are cosmetic home activities, not simulated wellbeing, resources, incidents
or operational outcomes. See the [social production source](../assets-production/characters/shift-social/README.md)
and [native animation evidence](../evidence/shift-change/animation/README.md).

## Evidence and its limits

The [physical checks](../evidence/shift-change/physical/README.md) passed all 70
directed anchor/workstation routes and actual five-crew home → work → home travel.
Each final home arrival stopped with an empty route and zero commanded motion,
0.102–0.114 m from its anchor. Failed old-spawn and seat-grid attempts remain in
the evidence. Shared reservations, interruption, fast completion, offline/reduced
holds, and collision-stalled routes have focused regression coverage.

The [native domestic and journey rehearsals](../evidence/shift-change/native/README.md)
passed using explicit offline fixtures. Domestic captured seated life, stand-up
interruption and fast-report evidence. Journey captured physical workstation
arrival, immediate terminal evidence, return home, a brief-job redirect, offline
hold and reconnect. Initial actors were explicitly staged one metre from anchors;
subsequent travel used actual physics. These runs issued no production commands.

Native social corrections now have separate contact evidence. Earlier malformed
skin, inherited rest-channel rotations and Sentinel thigh penetration are retained
as failures rather than hidden by passing clip-name checks. The native journey's
original return framing used a short camera-settle interval; its subsequent
120-frame correction passed in the final exported app. The [delivery record](../evidence/shift-change/README.md) binds the exact artifact and inspected captures.
Rehearsal capture timings include rendering and PNG work and are not an FPS
improvement claim. Owner visual approval is distinct from these technical checks.

## Remaining real-production acceptance

Retain native captures with actual authoritative run/duty IDs for these journeys;
the offline rehearsals above do not establish their production acceptance:

1. **Fast completion:** observe a real job that finishes before arrival. Its
   result must appear immediately without invented or prolonged console activity.
   The crew strip and structured inspector must expose the same retained evidence.
2. **Pause:** pause an enabled duty in Godot, verify Core's retained paused state
   and no later dispatch, and preserve any already active run until its actual
   terminal state. This real pause journey remains pending.
3. **Offline and reconnect:** interrupt the live client connection, verify honest
   last-known state and stopped work gestures, then reconnect without replaying
   obsolete trips or losing evidence.

Closed/open interiors, reduced motion and text scaling passed local qualification.
The final manifest binds the native captures to the qualified unsigned artifact;
this does not replace the real-production journeys above.

## Proposed follow-ups

Building aggregate badges showing active assignment counts and recent result
availability are **not implemented**. Completion requires an exterior-visible,
keyboard-accessible inspector link derived from authoritative records, with stale
and unknown states, plus native acceptance. The implemented crew strip is separate.

Additional scan/read/type gestures require actual phase events and freshness
semantics before they can represent work. A generic running state does not prove
model inference or a provider request. Further decorative art and ambient activity
may enrich the colony without creating operational claims. Persistent memory is
a later, separately gated backend capability.
