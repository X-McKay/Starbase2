# Continuous 3D colony validation

Status: proposed

Final result: full world/native command suite passed; the stable unsigned macOS
package qualified. Documentation, Python lint and whitespace checks passed.
See [validation summary](validation.json).

Branch: `feature/meshy-blender`. This extends the prior
[Meshy/Blender pass](../meshy-blender/README.md). No additional Meshy credits spent.

The original [baseline](before.log) reproduced the unavailable exterior-to-interior
route. The [first journey run](journeys-first.log) found console clearance failures.
Moving consoles back made all five journeys pass in [the corrected run](journeys-refined.log).
The first native view found floors hidden under paving and door origins overwritten;
the final Blender build raises floor surfaces and runtime doors retain their origins.

- [Engineering](engineering.png): visible interior floor, repaired model, reactor, crew and open door.
- [Colony](colony.png): all five native exterior shells in the existing terrain.
- [Botanical House](greenhouse.png): furnished grow beds, console and continuous surroundings.
- [Command](command.png), [Training](training.png), and [Habitat](habitat.png): remaining furnished rooms.
- [Asset inventory](assets.json): hashes, sizes and triangles for shipping authored GLBs.
- [Room controls](rooms-refined.log): walking, collision recovery, inspection, offline state and direct visits.
- [Full regression output](world-final.log): world checks followed by native command checks.
- [Package output](export-final.log): unsigned macOS resource/playback verification.
- [Rejected candidate](export.log): source-hash fence rejected a build during a whitespace edit.

Failures are retained rather than overwritten. Historical tests that required
hidden outdoor scenery and an entirely solid building footprint were updated to
check continuous surroundings and the actual wall/furniture collision segments.
Legacy illustrated-asset fixtures still validate their original rendering mode.
The crew share one repaired geometry with role colors; unique sculpts, facial
animation, hand/foot IK and authored work gestures are not included.

Native captures use the Compatibility renderer on Apple M5. Their adjacent JSON
files contain unbenchmarked frame samples, not evidence of a performance gain.
The overview and Botanical capture explicitly display a synthetic/stale fixture;
Engineering displays disconnected state. No commands were sent by walking or entry.
