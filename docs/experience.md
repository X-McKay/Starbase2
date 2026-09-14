# A world worth watching

The [Meshy/Blender pass](meshy-blender.md) implements the owner's native 3D direction
across the five-building colony and shared skeletal crew roster. Walk through
opening airlocks into furnished interiors as roofs fade and the camera eases in.
Structured inspection and authoritative state remain available. This supersedes
the earlier sprite-only and detached-room presentation on this branch.

Status: proposed

## Game-view polish · 2026-09-13

F1 or the HUD button collapses exploration navigation, roster and interaction
chrome; the header retains a restore action and keyboard workspace routes remain
available. The expanded roster respects the wide navigation rail. Compact
workspaces reserve less top space. Nearby station labels leave clearance above
the operator and doorway; distant labels are restrained.

Empty assignment, target and build selectors now explain what is unavailable.
Idle states and disabled actions use neutral emphasis. Station observation
summaries have a keyboard-accessible details disclosure retaining the exact
observation time and snapshot-window limitations. Dense panel surfaces are more
opaque. None of these presentation actions dispatches operational work.

## Ember console workspaces · 2026-09-11

The implemented Godot UI follows the approved orange workspace concepts: neutral
smoked charcoal panels, subdued blurred scenery behind the panel surfaces, ivory
text, and ember-orange selection, focus and primary actions. The shared theme
keeps text opaque; a screen-reading shader softens the scenery instead of adding
animated smoke. The native colony remains the surrounding experience.

Named navigation routes expose Map, Crew, Work, Stations, Field operations,
Settings and Connection. Wide windows use a left navigation rail; compact windows
use a horizontal strip. The crew dossier pairs the actual character portrait with
Overview and Evidence tabs. Mender alone also has isolated Practice; selecting a
record or watching a crew member does not dispatch work. Mender progression
remains distinct from operational permission.

Work groups Review, Compare, Duties and History. Field Command retains its
Observations, Repositories, Memory, Evidence and Duties workspaces. Forms group
inputs and policy context around their existing actions; retained evidence keeps
its exact identity and source qualification. Connection separates receipt/worker
status and endpoint controls from configured capabilities; enabled policy is not
proof of provider health. Settings groups Display, Audio and Controls and labels
boolean preferences with explicit On / Off values.

Station records and Habitat briefing share search, state filters, timestamped
rows and a wide-screen selected-record detail column. Compact rows retain exact
identity, outcome and evidence qualification when that detail column is hidden.
Station records show at most twenty retained snapshot records, open work first;
the Habitat briefing shows at most five terminal records with separate open-work
counts. Neither view claims complete historical coverage. Inspect routes to the
exact record and context; repeated unchanged polling preserves the pointer target
and keyboard focus. Unknown, disconnected/stale, failed, cancelled and missing
evidence remain distinguishable.

The `ember implementation evidence` (local review evidence is retained outside this commit)
records native review at 1280×800 and 800×640 with larger text, including a passed
27-view fixture run and independently reviewed corrections to compact Field
Command density, directory organization and active-workspace navigation. Full-suite
completion and standalone export qualification are tracked there separately. These source-checkout captures are synthetic review evidence,
not proof of live provider behavior or deployment of the new client.

## Faster exploration and expansion land · 2026-09-07

Keyboard and click-route travel now use 6 m/s (previously 3.7 m/s). Route steps
cap movement to the remaining distance so the faster pace cannot overshoot a
nearby waypoint. Actual displacement continues to drive the existing walk clip.
Visible Zoom in/out buttons, +/− keys and the wheel share bounded zoom in outdoor,
interior and map views. Reduced motion applies zoom immediately.

The playable outline is 40% wider and 35% deeper, providing 89% more area. Existing
structures keep their coordinates. The same expanded outline owns the cap,
cliff collision, navigation and northern mainland seam; the overview camera fits
the larger plateau. A subsequent rear expansion adds another 35% width at the
northern edge, tapering smoothly to the unchanged midsection and front. Northern
shoreline anchors follow the widened shoulders. New construction, roads and
district assets are future work.
See [exploration evidence](../evidence/colony-expansion/README.md).

## Asset-driven buildings · 2026-09-06

The [building catalog](building-catalog.md) separates PNG/native exterior assets,
placement, collision, and optional authored interiors. The Engineering Hangar now
sits beside the landing district. A searchable directory provides direct room
visits; the existing evidence and command boundaries are unchanged. A shared-art
50-instance fixture establishes reuse, not 50 unique-art memory qualification.

## Geology and connected paths · 2026-09-05

The [geology pass](world-geology.md) replaces repeated cliff stripes with painted
fractured rock, deep buttresses, a broken escarpment and soil-to-caprock blending.
Curved colony corridors connect existing districts; the safe shelf boundary and
all operational state remain unchanged. A connected mainland and headlands now
place the colony in a wider coastal landscape. The natural-outline pass reshapes
the playable shelf into rounded shoulders, headlands and coves; surrounding
mainland remains decorative, with navigation and collision confined to the shelf.
The upland transition now shares the exact shelf edge and soil shading, with
eroded ridges and clustered outcrops replacing the separate pale wall.

## Playable kit rollout · 2026-09-05

The [approved kit now appears in the colony](world-rollout.md): three textured
main buildings, plaza and habitat cladding, plus workshop, command and trial-hall
interiors. Doorway/inspector visits, bounded walking, console inspection and
return journeys preserve the existing authoritative state and non-spatial controls.
These instanced interiors supersede earlier notes that all interiors are deferred.

## Modular art pilot · 2026-09-05

The [art-production workflow](art-production.md) introduces a separate native
showroom with shared PNG surfaces and reusable interior/exterior modules. It
establishes an implementation path; playable interiors and the production quality
bar remain open. The running colony is not replaced by the showroom.

## Implemented cliff shelf · 2026-09-05

[The exposed colony shelf](world-cliff.md) replaces the enclosing rock barriers
with a near-side drop and connected rear escarpment. One irregular polygon owns
the rendered rim, physical edge and navigation clearance.

## Implemented red-planet surface · 2026-09-05

[The mineral basin](world-surface.md) adds red clay, cracked flats, dune shading,
stratified cliffs, golden groundcover, a turquoise pool and weathered landmarks.
This supersedes the first colony pass’s muted brown/green surface palette.

## Implemented planetary colony · 2026-09-05

[Aster colony](world-colony.md) expands the playable footprint into a planetary
basin with trails, a landing district, habitat, botanical module and reserved
sites. Follow/room cameras and a colony overview support exploration. This
supersedes the floating-terrace setting; construction and resources are scenery.

## Implemented space-adventure direction · 2026-09-05

[Aster frontier](world-adventure.md) adds four distinct higher-detail crew suits,
matching inspector portraits, a command bridge, engineering hangar, trial-hall
gate, airlocks and a ringed-planet backdrop. This supersedes the earlier cozy
solar-roof art direction; backend records and operational semantics are unchanged.

## Implemented playable art pass · 2026-09-05

[Aster outpost](world-playable.md) replaces the static blockout with original pixel
characters, textured habitats, walking/collision, contextual inspectors, native
synthetic repair commands, and core-backed achievement displays. Normal, compact,
large-text, stale and offline captures are retained. Interiors, work-stage
animation, sound, persistent decoration, and direct gym configuration remain open.

## Inhabited station refinement · 2026-09-10

The `next Morning refinement` (local review evidence is retained outside this commit) tightens
optional observation around actual crew, uses direct cuts between selected
inhabitants, and retains pending assignment changes through a minimum shot.
Lighter suit material response, domestic shelves and woven accents make the
existing rooms easier to read. Exterior station signs summarize retained records
and open native station records; Stations [I] provides the same structured
destination. Four-sample edge smoothing softens furniture and character outlines. Local
technical qualification and owner visual judgment remain separate.

## Native application direction · 2026-09-10

The [Habitat visual guide](../.agents/skills/starbase2-world/references/visual-guide.md#inhabited-habitat)
extends the inhabited world with optional close observation [V], a physical
Habitat daybook and historical briefing [K], authored handheld work equipment,
and warm domestic detail. Its acceptance bar is an understandable minute of
ordinary activity that the owner wants to keep watching. Native technical proof
and owner visual judgment are recorded separately in the
`integration evidence` (local review evidence is retained outside this commit).

Godot is the product interface for the world, structured operations, observability,
and operator actions. J opens native operations. Browser dashboard delivery is
retired: Core's root page provides connection guidance and preserves the native
operator-session handshake, while versioned APIs remain available. The old console
source is historical and is not served. Independent CLI/GitOps emergency stop
remains available when the renderer cannot run.

Native acceptance must exercise every enabled capability with keyboard access,
retained evidence, pending/unknown outcomes, reconnect, and stop controls. In
particular, configured field targets must support manual inference opt-in and
recurring duty creation/editing without a browser. Disabled memory and repair
capabilities must remain explicitly disabled; their complete native evidence and
control journeys are gates before later activation. Screen-reader support requires
native qualification; a retired browser UI is not evidence of accessibility.

## Historical local repair extension · 2026-09-05

Mender now has a persistent identity, 25 XP per distinct verified synthetic AI repair, two evidence-linked achievements and a level display in both clients. Qualification remains exact-build and permissions remain independent. This provisional progression curve is implemented, not usability-validated; see [repair operations](repairs.md).

Implemented UI: the [local operations edition](operations.md) now has a responsive
journal with review/gym/duty commands, stable Surveyor/Trainer role projections,
run history, source citations, keyboard controls, and a decorative station
illustration. Native Godot consumed the same v2 records and originally opened the browser journal
for review/gym/duty commands. That browser dependency is superseded by the native
application direction above.
The broader character simulation below remains proposed.

Earlier experiment: [Surveyor’s terrace](local-slice.md) had three static
crew, three work areas, a live mission inspector, and a keyboard-accessible
journal. Native rendering/export is demonstrated; final art direction, animation,
web delivery, and accessibility/performance budgets remain proposed.

## Direction

Build an inhabited planetary research colony: a small established civic center,
newly landed equipment, surveyed sites and surrounding terrain with room to grow.
The owner selected this direction after reviewing the space-adventure crew and
station art. Prefer refining these authored districts over generating an endless
map or adding operational systems solely to fill the landscape.

Use Godot 4 with an orthographic 3D environment, restrained geometry, and
expressive billboard/sprite characters. Compose scenes in the editor and
version their text assets. Favor a few beautifully authored spaces over a
large procedurally generated map. Create original assets with provenance.

Godot is the selected product renderer for scene authoring, lighting, pathfinding,
character animation, and camera work. Native desktop qualification is the current
delivery path. Any future Godot web export must be qualified separately; it uses
WebGL 2 and Compatibility rendering.
[Godot export constraints](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)

## Three layers, one coherent experience

**World:** location, activity, workload, and attention are readable at a glance.
**Inspector:** a crew member, work item, or place opens a concise explanation.
**Evidence:** one more step reveals source facts, diffs, traces, or trial data.

Keep the world prominent. The inspector is a legible dock beside it, not tiny
text pasted onto walls. Structured native operations use the same authoritative
projections and command semantics inside Godot, with pending states and
uncertain-response reconciliation. Evidence and commands must not launch a browser.

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
operation, and native screen-reader access. Screen-reader acceptance remains open. Test full, compact,
empty, stale, burst, failure, and reconnect states.

First art spike: three crew, three adjacent spaces, 20 active task markers, and
a bounded burst of 100 updates/second. These are proposed test conditions,
not measured system capacity. Record frame time, memory, startup/download,
projection lag, and time to reach evidence. Stop expanding the map until the
small scene is readable, enjoyable, and technically sound.

The Engineering review slice adds a generated PBR hull and reactor around an
authored continuous interior. The player uses CyberCat Vanguard; Mender retains the detailed Engineering
suit. Running follows actual displacement; Mender's console
gesture follows local inspection in Engineering, never inferred operational
activity. Reduced motion freezes the decorative effects and skeletal animation;
reactor sound defaults off. The [review notes](../assets-production/batches/engineering-polish/REVIEW.md)
define the bounded milestone and remaining visual review.

### Crew workflow guide

Crew dossier Overview leads with an authored purpose, skills/workflows, scope,
and a keyboard-accessible action that opens the appropriate setup form. Rivet
opens repair Practice; Moss opens Review; Mae opens Compare; Wes and Prism open
Observations and select a matching configured target when available. Opening a
form never submits work. Evidence contains the assignment selector, cancellation,
retained result details, and Rivet's verified progression.

Descriptions explain the implemented workflow, not installed runtime skill
packages or proficiency. Installation policy, disconnected state, worker status,
and fixture mode remain explicit; the submission form validates actual readiness.
The backend does not currently provide a named runtime skills catalog.
