# Crew environment interactions

Status: proposed

Implemented and locally verified, including the full world suite and unsigned
macOS export. Owner: World. Owner art acceptance remains separate.

Crew work uses reachable station surfaces: a supported keyboard tray, display,
and tactile control. The station is placed at the existing crew work anchor and
oriented toward its room equipment. Each character keeps its own rig, proportions,
and locomotion. Hand targets are world transforms, so the pose follows the actual
furniture rather than an unrelated animation loop.

Shared actions are settling into reach, alternating key presses, reading the
screen, a brief screen/control gesture, and withdrawing. Role variations are
presentation mannerisms: Rivet adjusts a control, Moss scans and gestures across
a schematic, Mae compares screen sections with a quicker typing cadence, Wes
scans with a tactile control gesture, and Prism uses a deliberate screen gesture.
These do not describe actual reasoning stages, tool calls, or successful work.
Screens contain static diagrams, not invented telemetry or progress percentages.

The authoritative projection still owns eligibility. Fresh running work can use
a station only after physical stopped arrival. Queued, blocked, cancelled,
completed, stale, disconnected and unknown work cannot activate contact feedback.
Reduced motion clears the gesture and input movement. Seated crew retain a neutral
seated posture through waiting, stale and disconnected states. Reconnecting does
not replay sitting. Departure completes standing before physical travel;
authoritative cancellation and results appear immediately and never wait for it. Where a station is unavailable, the existing
handheld presentation remains available. Structured Crew and Work views retain
exact state, evidence and stop controls independently of animation.

## Furniture and movement

Wes and Prism use seated Command chairs facing the large displays. Their chair-mounted
keyboards deploy after seating; arrival and departure include foot adjustments and
sit/stand transitions. Rivet and Moss use trays attached to existing desks, while
Mae uses a standing simulator console. The support footprint feeds both physics and navigation. The visible station
root uses the same imported floor-height sampler as crew soles, while navigation
remains planar. Final workstation approaches stop within 15 mm, with contact
eligibility bounded to 25 mm; ordinary travel and home tolerances remain unchanged. Raised trays
have a supported overhang for the short rigs' reach; native review must check
actual torso and hand clearance rather than treating the broad movement capsule
as an anatomical model.

A new stand exposed an existing navigation-grid assumption: an exact safe station
point could round into a blocked half-metre cell. Endpoint recovery now searches
neighboring clear cells and requires a safe connecting segment. New supports keep
40 cm routing clearance; no collider is removed to make a journey pass.

Seated arrival first settles and aligns on the actual chair axis. Grounded foot
adjustments then bring the body into the cushion. Departure withdraws hands for
0.32 s, stows the keyboard for 0.28 s, and completes standing before travel.
The two chairs retain their full collision bounds and collision-safe approaches.

Detailed contracts: [animation and skin calibration](workstation-animation.md)
and [furniture and contact frames](workstation-affordances.md).

## Review and completion

Technical qualification requires all five crew to physically arrive from home,
use their own contacts, release on invalid work state, and return home. Rig tests
must sample poses after engine updates at 30, 60 and 120 Hz. Native front/side
views must show credible contact and a readable action at gameplay scale. A
contact-distance test alone does not establish finger placement or visual quality.

Evidence and final results belong in
[the interaction review](../evidence/world/environment-interactions-20260928/README.md).
The previous qualified build predates these changes. Owner art acceptance is
separate from technical qualification.

## Further action vocabulary

World owns these future slices, each requiring authored contact geometry and
native interruption evidence before it is enabled:

| Action | Purpose and completion condition |
| --- | --- |
| Tool rack selection and replacement | Rivet picks up a specific attached tool, uses a reachable service panel, and returns it without prop popping or obstructing cancellation. |
| Shared screen briefing | Two reserved crew positions support gaze and pointing at one display without overlap; ambient conversation stays distinct from recorded coordination. |
| Simulator controls | Mae manipulates separate controls with visible response tied to contact, while evaluation outcomes remain authoritative records. |
| Inspection walk | Wes inspects existing physical stations along safe reserved stops; visits do not invent incidents or observations. |
| Desk annotation | Moss and Prism use a supported slate or writing surface with explicit hand/prop ownership and interruption-safe replacement. |
| Commons everyday activity | Cup handling, reading and tending plants use reserved anchors and grounded props; purely ambient actions never stand in for backend activity. |

No permission, capability level, evaluation result or external action is granted
by any of these gestures.

Hand-contact data is derived from the actual skin vertices weighted to each
rig’s hand bones; keyboard underside and screen-facing extremities use separate
probes. Preparation takes 0.46 seconds and withdrawal blends over 0.18 seconds,
without delaying root movement. The current five rigs have hand bones but no
separately skinned finger bones.
This slice uses rigid-hand typing and pointing; its contact measurements are
calibrated rigid-hand skin probes, not a claim of individually animated fingertips.
World/asset production owns a later finger-rig upgrade, complete only when skin
weights, existing clips, keyboard contact and interruption are verified across
all five characters in native playback.
