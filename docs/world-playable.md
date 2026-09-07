# Aster outpost: first playable art pass

Status: accepted

Date: 2026-09-05. Scope: local native Godot client. No deployment or backend migration.

## Implemented journey

`just world` opens an original space outpost with four animated pixel characters,
three reusable habitat scenes, solar roofs, ceramic panel textures, planted
walkways, hull depth, real directional shadows, and a distant planet. The user's
three supplied game images informed silhouettes, layered scenery, surface detail,
and readable paths; their artwork was not copied. Original editable SVG sources
live in [the art directory](../apps/world/assets/README.md).

Walk with WASD/arrows or click a path. Collision prevents walking through habitats
or off the terrace; click routing goes around obstacles. E near a crew member
opens its inspector. Clicking a character or using 1/2/3 reaches the same view
without travel. Tab opens the directory, Escape closes panels, J opens the
independent journal, C toggles camera follow, and the wheel adjusts zoom. H opens
help, larger text, and reduced motion. Enter activates the focused control.

Mender's workshop can launch either a clearly labeled synthetic known-good control
(no inference/XP) or a synthetic AI proposal (one model call through the existing
worker configuration). Pending requests disable duplicate submission. The native
client obtains the existing local operator cookie in memory; it never reads the
worker token, follows redirects, or accepts a remote command origin. A lost write
response triggers a record lookup, never automatic redispatch. An unresolved
lookup fences further dispatch until reconciliation. Cancellation uses the same
core endpoint as the journal, which remains available independently of Godot.

## State ownership and visual meaning

| Presentation | Authority and freshness | Evidence / failure behavior |
|---|---|---|
| Crew status and concurrent run count | Existing `/v2/snapshot`, core order, worker availability | Inspector selects retained runs; missing completion evidence stays unknown |
| Offline/stale labels | HTTP outcome and five-second freshness bound | Last-known data remains labeled; no new command is enabled offline |
| Run outcome and baseline/candidate score | Core-retained report or repair summary | Synthetic inputs, inconclusive results, failures and no-change remain explicit |
| Mender level, XP and cabinet trophies | Core progression ledger and achievement list | Initial load has no award celebration; unavailable data never creates trophies |
| Walking, idle motion, trees, lights and planet | Local decorative presentation only | No claim about agent thought, work progress, success or permission |

Data projection, navigation, native commands, HUD, actors, and reusable visual
components are separate small files. Scene instances and positions are authored
in `main.tscn`; room interiors are not implemented. No additional service or
persistent product store was introduced. The earlier scene was a blockout;
Godot remains suitable for this scoped native experience, with no web/platform
superiority established.

## Verification and retained evidence

- `just check-world`: import, state/order/missing evidence, route reachability,
  physical keyboard interaction, mouse routing, reduced motion, text bounds,
  offline command fencing, and a local HTTP failure fixture. That HTTP fixture
  checks cookie identity, denied requests, duplicate inputs, lost responses and
  GET reconciliation without another POST. It dispatches no real work.
- Native scripted walking reached Mender through the actual physics loop:
  [capture and metrics](../evidence/world-playable/walk.png.json).
- Native command `world-visual-control-01` completed through the existing local
  Temporal worker and real microsandbox VM. The core retained baseline 5/6,
  candidate 6/6, no hard-gate failures, and **zero XP** for the deterministic
  control. [Full retained record](../evidence/world-playable/repair-control.json).
  No model call was made in this UI experiment; inference was exercised in the
  earlier repair milestone, not re-qualified here.
- Inspected actual renders at 1280×800 and 960×720, including larger text,
  reduced motion, missing core, and a prominently labeled synthetic stale/failure/
  inconclusive fixture. See [outpost](../evidence/world-playable/outpost.png),
  [repair result](../evidence/world-playable/repair-command.png),
  [disconnected](../evidence/world-playable/disconnected.png), and
  [compact stale fixture](../evidence/world-playable/stale-compact-final.png).
- One short uncapped capture on Apple M5 / Godot 4.7.2 Compatibility reported
  3.70 ms median and 4.17 ms p95 engine frame intervals over 210 post-warmup frames,
  341 ms to first frame, and 800 draw calls. These are engine-loop observations,
  not GPU timing, a load benchmark, or an older-device guarantee.
  [Raw measurements](../evidence/world-playable/outpost.png.json).

Preserved failures include the initial overbright/distant render, compact
large-text overflow, the pre-existing reversed repair-order regression, and
keyboard/mouse test harness mistakes (missing release, input-buffer flushing,
and OS pointer focus in headless mode).
The ordering regression and layout were fixed; the harness now exercises actual
input dispatch. Sandboxed macOS prevented the first native launch and editor
settings writes; normal macOS access was used for successful native verification.

Final gates passed: 27 Rust tests, 16 Python tests, repository lint and contract
checks, 29 Markdown documents, and the complete Godot suite. See the
[machine-readable handoff](../evidence/world-playable/validation.json) and
[Godot log](../evidence/world-playable/check-world-passed.log).

## Remaining product work and completion conditions

Owner: Starbase2 development, with Al reviewing art and interaction direction.

- **Interiors and work gestures:** enter a small authored workshop/gym; map each
  meaningful animation to a retained execution stage and test reconnect/skip.
  Current idle movement and empty gym plinths are decorative.
- **Deeper art and sound:** refine original sprite poses, foliage and prop variety;
  add licensed/original footsteps and ambience with a mute control. Current audio
  is off and characters use a minimal two-frame, four-direction walk cycle.
- **Gym interaction and customization:** support direct paired-build configuration,
  evidence-linked replay, and persistent decoration placement. Gym/review creation
  currently opens the journal; native direct creation is limited to repair.
- **Comfort and delivery:** persist comfort settings, test gamepad and screen-reader
  journeys, measure larger/event-burst scenes and other hardware, and validate web
  delivery. Current comfort settings last for the session. The structured journal
  remains the non-spatial accessibility path; this is not a full accessibility audit.

Kubernetes deployment remains a separately scoped task. This playable art pass does
not qualify production authority, arbitrary repository repairs, or general agent
improvement.
