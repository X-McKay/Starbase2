# Cinematic crew presentation

Status: proposed

Implemented and locally verified on 2026-09-28. Owner: World. Owner visual
acceptance and packaged-build qualification remain separate.

The world now composes crew work as a continuous physical performance. Optional
Observe mode eases among medium, over-shoulder and equipment views without moving
the crew or changing a record. Indoor views use the established cutaway side of
the room so opaque exterior walls do not block the selected worker. A subject
change keeps the camera continuous; each subject holds for at least six seconds
and each composition for 5.5 seconds. Reduced motion keeps Observe disabled.

Locomotion derives from measured displacement. Start and stop blends, acceleration
lean, turning lean and idle cadence vary by crew class while feet, root height and
collision stay governed by the existing contact and navigation systems. The six
profiles make Rivet read heavier and more deliberate, Mae quicker, Wes steadier,
and Prism precise without changing travel speed or operational priority.

The 2026-10-03 refinement lets the upper torso lead a corner before the root
finishes turning, then briefly settle after a stop. The overlay leaves hips,
navigation and planted-foot correction alone. Its class-specific response is
checked on imported rigs at 30, 60 and 120 Hz.

Workstations use deterministic role vocabularies rather than one repeated loop.
Typing, reading, comparing, scanning, inspecting, annotating, demonstrating,
pointing and control gestures all target the real keyboard, screen and control
transforms. Command crew sit in their chairs before the tray deploys and work
begins. These actions describe presentation style only; they do not claim private
reasoning, a tool call, task stage or success.

The standing display now gives local feedback only while a real screen contact
is active. Seated Command displays respond to actual keyboard or control contact
after tray deployment; losing that contact clears the cue. The display feedback
is decorative and cannot imply task progress or success.

## Recorded handoffs

When a fresh SDLC V7 snapshot gains an exact adjacent role transition, the two
mapped crew members navigate to reserved Commons positions. The transfer token
appears only after both routes finish. Each rig then looks toward its partner and
solves its own right-hand contact to the same token. The exchange clears after six
seconds, after 75 seconds without arrival, or immediately when reduced motion is
enabled.

Retained history does not replay at startup. Unchanged polling, stale data,
same-role transitions and reduced motion cannot start an exchange. The controller
chooses the most recently updated mission independently of list order, coalesces
to one current presentation, and never mutates the snapshot or calls a command.
Labels and structured Work views continue to carry authoritative state and exact
evidence while crew travel catches up.

Observe tests multiple bounded sightlines against world collision before picking
a work or two-crew handoff view. A newly recorded handoff can receive the next
eligible Observe shot without interrupting its six-second minimum hold. Camera
choices never change the rendezvous or the underlying record.

## Qualification

Focused checks cover camera selection, all six work vocabularies, class movement
continuity at 30/60/120 Hz, actual workstation arrivals and contacts, two-rig
handoff reach, the full navigation-to-exchange journey, no-dispatch behavior and
reduced-motion interruption. Native review captured seated Command work in three
compositions and the shared Commons exchange. The first capture retained in the
evidence directory exposed wall occlusion; the corrected views use the safe
cutaway side.

See [native review evidence](../evidence/world/cinematic-crew-20260928/README.md).
The [Observe camera review](../evidence/world/observe-camera-20261003/README.md)
and [display response review](../evidence/world/station-display-response-20261003/README.md)
show the 2026-10-03 source-checkout frames.
Individual finger articulation, multi-person briefings, carried tools and ambient
conversation remain later asset and choreography work. The current rigs expose
rigid hand contacts, so this implementation does not claim finger-level typing.
