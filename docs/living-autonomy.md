# A miniature autonomous world

Status: proposed. Owner: implementation assistant; Al reviews the native journeys.
This plan changes presentation after the current autonomous-duty, real-work LLM,
and Godot-only acceptance journeys pass. Persistent memory remains deferred until
those three are accepted; it is not a prerequisite for visible crew activity.

## What already works

Real V4 field runs already reach the world. Watchkeeper and Reviewer travel to
separate workstations inside Command. Queued work requests travel; running work
requests a console animation only after physical arrival. Completion with
retained evidence shows an evidence marker and returns the actor home. Failure,
cancellation pending, stale state and disconnection remain distinguishable.
Arrival never dispatches, delays or completes backend work.

The existing five-crew physics test verifies routes, airlock entry, continuous
movement and workstation poses using long-running fixtures. It does not prove
that short real observations remain visually legible. Runs can finish between
snapshot polls or before the actor arrives. Crew inside closed interiors are
hidden from the exterior camera. There is currently no authored home/social destination between runs: `CrewMotion.rest`
is the actor's starting position, with a nearby-station offset workaround when
that point overlaps its workstation. A stalled route stops without an explicit
navigation status. These are the first gaps to address.

## First implementation slice

Make the existing Habitat, break-room furniture and Commons the crew's home
between assignments. Idle characters relax, sit, rest or hang out at authored
social anchors, including when an enabled duty is waiting for its next dispatch.
The label **On duty · waiting** describes scheduling, not a requirement to sit at
a workstation. A paused duty can use the same ambient home behavior with an
explicit paused label.

A real queued assignment interrupts ambient activity and requests travel to the
appropriate workstation. Running work uses the existing console pose only after
physical arrival. Completion publishes its result immediately and requests a
return to Habitat or a chosen Commons anchor when no other active assignment
remains. If a job finishes en route, show **Report ready** immediately and turn
home without inventing a console session. Pausing future dispatch does not stop
an already active run or justify sending its actor home early. Arrival never
gates backend execution, evidence or completion.

Add a compact building badge showing assigned active counts plus recent
result availability. It remains visible when the interior cutaway is closed and
opens the existing structured inspection path. Offer an explicit **Watch crew**
camera action; never redirect the camera automatically. Show a cosmetic
**Route blocked** marker when navigation cannot reach its destination, alongside
the unchanged backend status.

| Authoritative input or local condition | Presentation | Files |
| --- | --- | --- |
| Fresh `/v4/snapshot` duty enabled; no active run | Habitat/Commons relaxation; on-duty waiting label | `apps/world/command_board.gd` emits its existing snapshot projection; `world.gd` forwards it; `crew_presentation.gd` selects intent |
| V2 snapshot `field_runs`: queued | Assignment marker and optional station travel | `apps/world/state.gd`, `crew_presentation.gd`, `crew_motion.gd` |
| Field run running and actual station arrival | Existing console pose; active count and run identity | `apps/world/crew_motion.gd`, `actor.gd` |
| Completed run with retained evidence | Immediate result marker; return Habitat/Commons when no active assignment remains | `apps/world/state.gd`, `crew_presentation.gd`, `actor.gd` |
| Retained `inference_budget` skipped | Explicit hourly/daily limit reason, without implying reasoning occurred | `apps/world/state.gd` preserves budget metadata; `crew_presentation.gd` and structured inspector render it |
| Duty paused; no active run | Continue/return to Habitat or Commons; paused label | `apps/world/crew_presentation.gd`, `crew_motion.gd` |
| Failed or cancellation pending | Distinct text/icon; stop work gesture as appropriate | `apps/world/crew_presentation.gd`, `actor.gd` |
| Stale snapshot or disconnected client | Hold motion, suppress confident work, retain last-known evidence with freshness | `apps/world/world.gd`, `crew_presentation.gd` |
| Empty or stalled navigation route | Local route-blocked cue; domain state unchanged | `apps/world/crew_motion.gd`, `actor.gd` |
| Aggregate station assignments | Exterior active/result badge and inspector link | `apps/world/world.gd`, station presentation and `hud.gd` |

Keep snapshot projection separate from rendering. Reuse the existing field
snapshot polling rather than adding another renderer-owned request loop. Carry
observation timestamps and connection state with duty data. Reconnect replaces
obsolete motion intent; concurrent runs retain one stable crew identity and
separate task markers. Reduced motion preserves all labels and evidence while
removing cosmetic movement. Keyboard navigation and the structured inspector
must expose the same state without requiring camera travel.

## Existing places and anchors to author

`apps/world/structures/colony.tscn` places Habitat at world `(36, 0, -15)`.
`structures/definitions/habitat.tres` already defines its seamless interior,
doorway approach/threshold and furniture navigation blocks.
`structures/interiors/habitat-continuous.tscn` contains a galley at local
`(-7.75, 0.15, -4.35)`, a lounge sofa at `(7.8, 0.15, -3.75)`, and three sleep
capsules at x `-5.22`, `0`, `5.22`, y `0.15`, z `-9.85`. These are prop transforms,
**not qualified actor destinations**. Existing generic markers are Spawn
`(0, 0, 0.7)`, Console `(-0.7, 0, -2.65)`, Crew `(1.75, 0, -5.15)` and WalkTarget
`(-2, 0, -4.85)`; none defines individual seats or social occupancy.

`apps/world/living_commons.gd` places the shelter/garden at `(-7, 0, 23)` with
explicit collision blocks. It has no crew seat, rest or social markers. Reuse
these existing places and furnishings; author named seat/standing/rest anchors,
entry/exit approach points, facing, pose compatibility and bounded occupancy.
Do not place actors at furniture origins or disable collisions to make them fit.

Extend `crew_motion.gd` from its single work-station visibility reference to
resolve the actor's current building while routing between Habitat, Commons and
workstations. Qualify door clearance and interior cutaway visibility at both
ends; preserve the operator's room and camera. Add comfortable idle/social pose
variants in `apps/world/characters/model_visual.gd` and its authored animation
assets as needed. Sitting/resting poses require seat alignment and transitions;
existing generic idle/console clips are not evidence of this capability.
Ambient anchor selection is cosmetic and must not invent job or health records.

## Later visual enrichment

Use distinct scan, read, type and review gestures only when corresponding phases
are actually recorded by the backend. A generic running state does not prove
that the model is thinking or that a provider is being queried. Add phase events
and their freshness/replay contract before mapping them to new workstation
animations. No minimum fake-busy interval should stretch a completed job merely
to show an animation.

Habitat, Botanical and Living Commons may host clearly decorative idle movement,
conversation and environmental animation. `apps/world/living_commons.gd` remains
scenery: ambient activity cannot imply jobs, resources, wellbeing measurements,
success or incidents. Additional Meshy/Blender assets can enrich this layer after
the first truthful duty presentation is legible.

## Acceptance journeys

Extend `apps/world/test_crew_presentation.gd` and `test_live_crew.gd` for Habitat/Commons
idle anchors, cross-building travel, pause, fast completion, concurrent work and
blocked routes. Then retain
native captures from three real journeys, with authoritative run/duty IDs:

1. **Fast completion:** observe a real job that finishes before arrival. Its
   result appears immediately, with no delayed completion or invented work pose.
   The building badge and keyboard inspector expose the same evidence. The actor
   returns toward its home/social anchor without a fake console visit.
2. **Pause:** pause an enabled duty in Godot. The paused state is confirmed by
   Core; no further dispatch occurs. Any active run stays accurately represented,
   and the actor returns home only when there is no active assignment.
3. **Offline and reconnect:** interrupt the client connection. Work gestures stop
   and last-known state is explicit. Reconnect coalesces to the current run/duty
   state without replaying obsolete trips or losing evidence.

Inspect these journeys with closed and open interiors, reduced motion and text
scaling. A passing fixture or headless test is not a substitute for the actual
native experience. Record remaining limitations before Al accepts the slice.
