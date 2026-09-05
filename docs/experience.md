# A world worth watching

Status: proposed

## Direction

Build a compact research settlement on a floating industrial terrace: warm
workshop windows, weathered ceramic panels, mechanical couriers, hanging
gardens, and a bright experimental gym. This is an initial art hypothesis,
not an inherited station layout or final brand. Also prototype an orbital
cutaway and a mobile research vessel before committing to the spatial theme.

Use Godot 4 with an orthographic 3D environment, restrained geometry, and
expressive billboard/sprite characters. Compose scenes in the editor and
version their text assets. Favor a few beautifully authored spaces over a
large procedurally generated map. Create original assets with provenance.

Godot is the leading renderer candidate because the desired experience needs
scene authoring, lighting, pathfinding, character animation, and camera work.
Test it against a small browser-native 2.5D alternative if download, accessibility,
or integration costs dominate. Godot web export uses WebGL 2 and Compatibility
rendering; native desktop and web must be measured separately.
[Godot export constraints](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)

## Three layers, one coherent experience

**World:** location, activity, workload, and attention are readable at a glance.
**Inspector:** a crew member, work item, or place opens a concise explanation.
**Evidence:** one more step reveals source facts, diffs, traces, or trial data.

Keep the world prominent. The inspector is a legible dock beside it, not tiny
text pasted onto walls. A compact web console uses the same projections and
command semantics, without requiring Godot. Initial Godot builds inspect and
deep-link to the console for actions; direct in-world commands follow only
after tested authentication, pending-state behavior, and accessibility parity.

Rooms are activity contexts. Operators do not need to know the backend topology.
An event animation is a projection of work; a character reaching a door cannot
start a workflow or block its completion.

## Places and their purpose

| Place | What makes it interesting | Operational evidence |
|---|---|---|
| Signal garden | Antennas and sensor drones notice changes at the perimeter | Source freshness, checkpoints, new observations |
| Commons | Crew meet, await assignments, and deliver a change-of-watch briefing | Duty roster, capacity, completed and pending work |
| Workshop | Patches take shape on benches and await a visible dispatch stamp | Exact diff, tests, target, plan, approval and verification state |
| Observatory | Scout assembles a constellation of related news and papers | Sources, dates, duplicate clusters, uncertainty |
| Gym | Baseline and candidate enter neighboring test chambers | Trial state, independent checks, resource use, result distributions |
| Archive | Persistent history becomes explorable without loading every transcript | Versioned memory, provenance, retractions, build lineage |

Ship the Commons, one Surveyor desk, and one gym chamber first. The names are
provisional; a new sensor or agent never requires a new building.

## RPG model

| RPG idea | Useful system meaning |
|---|---|
| Character | Stable crew identity across sessions and builds |
| Class | A displayable specialization assembled from demonstrated capabilities |
| Equipment/loadout | A pinned build of model, tools, prompt, skills, and memory policy |
| Quest | Bounded work with acceptance and authority |
| Practice arena | Public development scenarios |
| Qualification trial | Sealed, independently graded evaluation |
| Skill tree | Capability prerequisites backed by scenario families |
| Level and cosmetics | Historical recognition of verified contributions |
| License to act | Separate, plainly labeled operational permission |

Do not hard-code a rigid inheritance tree of agent classes. Compose capabilities
such as evidence reading, repository review, dependency repair, and source
verification. Crew personalities and silhouettes give continuity while builds
change. Cosmetic descriptions are separate from task instructions unless a
deliberate, evaluated prompt experiment includes them.

Start with an inspectable progression policy: published thresholds, versioned
award rules, and reversible ledger corrections. Exact XP curves await playtests;
inventing numerical precision now would distract from the useful feedback loop.
Unlock decoration and suggested practice, never credentials or mandatory
operational controls. No grinding requirement to access evidence or stop work.

## Make the gym the signature feature

Select a crew member, duplicate its build, change a skill, and put the builds
on adjacent gym benches. Each test chamber is a real isolated run. The room
shows attempts completing, failing, or waiting for infrastructure. Selecting
the comparison board opens per-case outcomes, regressions, costs, uncertainty,
and the exact loadout diff. There is an explicit "keep current build" outcome.

Let the operator replay a completed run as an annotated ghost rehearsal,
clearly labeled historical. A capability tree links locked branches to the
specific missing evidence. A failure museum collects instructive mistakes and
the regression tests they produced. A field journal celebrates verified
no-change decisions as well as successful repairs.

## Ambient life and truthful activity

Autonomous ambient behavior uses cheap deterministic character routines.
Idle crew may stroll, sit, water plants, or socialize without model calls.
These are clearly decorative; they cannot manufacture task progress, incidents,
reasoning, relationships, or conversations attributed to real agents.

| Backend state | World response | Inspector truth |
|---|---|---|
| Run accepted | Crew approaches a workstation | Accepted time and run ID; animation may lag |
| Evidence read | Desk lamp and document gesture | Bounded tool event and evidence reference |
| Waiting for model/tool | Crew waits at the station | Dependency, elapsed time, deadline |
| Awaiting approval | Sealed project tray | Exact action and missing decision |
| Independently verified | Report delivered; optional celebration | Verifier, checks, limitations |
| No change | File archived with a calm acknowledgment | Evidence supporting abstention |
| Worker stale/disconnected | Muted crew marker | Last-known state and freshness; outcome unknown |
| Run failed | Focused station indicator | Failure category and retained evidence |

Thought bubbles show verified activity summaries, not fabricated private
reasoning. Keep run state separate from agent availability: one crew member
may own several concurrent runs, shown as task markers rather than fictitious
extra characters. Reconnection snaps to current truth and suppresses obsolete
travel and celebrations. Visual coalescing never deletes audit events.

## Polish gates

Measure on named reference hardware with representative entity and event load:
target 60 fps for normal activity and a responsive 30 fps degraded mode. Keep
camera movement optional; reduced motion replaces travel with transitions.
Support text scaling, keyboard navigation, color-independent status, sound-off
operation, and screen-reader access through the console. Test full, compact,
empty, stale, burst, failure, and reconnect states.

First art spike: three crew, three adjacent spaces, 20 active task markers, and
a bounded burst of 100 updates/second. These are proposed test conditions,
not measured system capacity. Record frame time, memory, startup/download,
projection lag, and time to reach evidence. Stop expanding the map until the
small scene is readable, enjoyable, and technically sound.
