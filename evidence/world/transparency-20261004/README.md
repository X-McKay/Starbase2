# Live crew view captures · 2026-10-04

These are native Godot 4.7.2 captures of the [live crew view](../../../docs/live-crew-view.md),
taken with the OpenGL 3 renderer (Mesa llvmpipe) under Xvfb.

**All data is synthetic.** The stream replays `fixtures/world/transparency/stream.jsonl`,
which is paired with `v7-snapshot.json` and `world-snapshot.json`. The story is an
invented mission 42, "Fix cache eviction", on X-McKay/algent. No Core, worker,
model or repository was contacted, and the masthead says `SYNTHETIC REPLAY` and
`VISUAL TEST FIXTURE`. The fixture's timestamps are shifted to the time of the
replay, so the UTC times differ from run to run.

| Image | Shows |
|---|---|
| `live-crew-view.png` (1440×900) | Badge `[~] LIVE · last event … ago`, Reality Gate (gen 7, expires in 2d 14h, 1 / 3 missions used, policy `[=]`, test verdict `[=]` 6/6 vs 4/6 +6 −2, reviewer `[x]` changes requested · 2 findings, authority note), the last six live activity entries, the follow-card on Rivet (`[>] Running tests`, round 2, observed model requests and tokens) and `Running tests` in the crew strip. |
| `live-crew-view-stale.png` (1440×900) | The replay is paused until a heartbeat window is missed. The badge reads `[?] STALE · last event 11 s ago · heartbeat missed`, the card reads `[?] Activity unknown · stream not live`, the activity header reads `ACTIVITY · LAST KNOWN`, and the strip falls back to the record label. |
| `live-crew-view-compact.png` (960×700) | The same live state on a narrow window. The activity panel is collapsed to `[~] Activity · 6 [T]` and the gate is under the compact navigation. |
| `live-crew-view-compact-large.png` (960×700) | The compact view with larger interface text. Gate checks wrap instead of truncating. |

`captures.json` records the badge, activity, card, gate and strip text, the stream
state and the `/v7` snapshot age for each image. Each entry was written just after
its image was saved; on the software renderer a frame can take about a second, so
the ages in `captures.json` can be a few seconds later than the ones in the image.

Reproduce from the repository root:

```sh
xvfb-run -a -s "-screen 0 1440x900x24" godot --path apps/world --rendering-driver opengl3 --script capture_transparency_live.gd
```

The script fails if any of its truth checks fail. It printed
`TRANSPARENCY_CAPTURE_PASSED`. The only error logged was the container's missing
ALSA audio device (`ERR_CANT_OPEN`), which is harmless here.

Review notes: the follow-card can overlap world-space captions such as the Habitat
daybook label. Some crew-strip labels truncate as they did before this change.
Owner visual acceptance is pending.

## Captain's Log captures · page 4

These are native Godot 4.7.2 captures of the [Captain's Log](../../../docs/captains-log.md),
made with the same renderer and the same synthetic stream. The mission record shown
is `fixtures/world/transparency/mission-sdlc-42.json`, the synthetic full
`/v7/missions/sdlc-42` record paired with `v7-snapshot.json`. The stream header
names it under `v7_missions`. No request is made: the script checks that the log's
HTTP client stays disconnected. The header reads `SYNTHETIC REPLAY` and
`Synthetic fixture record`. Times are shifted to the time of each replay, so they
differ between images.

| Image | Shows |
|---|---|
| `captains-log.png` (1440×900) | Opened with **G**. Header: mission 42, repository, admission time, `now implementing round 2`, `19.3k tokens retained`, `cost not recorded`, `[~] LIVE … SYNTHETIC REPLAY`, `[=] Synthetic fixture record · 4 retained events`, and the current admission (labelled not a timeline event). The timeline has lanes for Moss, Rivet, Prism and Core with nine events: admission, source capture, plan, patch and grade (same time, two lanes), changes requested, and three hollow Rivet pins for live notes that Core does not retain. It also shows the mission state band, the collapsed `≈ 7 m quiet` gap, the dashed *now* line, tokens per crew, and the detail of the newest record (event 6, 2 findings, missing evidence, model usage, model reasoning not recorded, source `events[3] · key review-1`). |
| `captains-log-detail.png` (1440×900) | Pin 3 clicked, then `.`: event 4 *Patch round 1 · +6 −2* with diff stats, candidate run, artifact digest, stated rationale, model usage, *Model reasoning* and *Tool arguments* not recorded, and source `events[2] · key testing-1`. |
| `captains-log-list.png` (1440×900) | **L**: the chronological list, the non-spatial equivalent, with the same nine events, the same selection (row 4) and the same detail. Observations are marked `observed, not retained`. |
| `captains-log-compact.png` (960×700) | The timeline on a narrow window. Tokens fold into the lane labels, the detail column narrows, and the collapsed-gap label takes priority over time labels. |

`captures.json` gains a `captains_log` key with the title, meta, status lines,
selection, detail, *not recorded* lines, source, every list line and the tick labels
for each image. The slice 3 keys are unchanged. Running
`capture_transparency_live.gd` again rewrites that file without this key, so run
this script after it.

Reproduce from the repository root:

```sh
xvfb-run -a -s "-screen 0 1440x900x24" godot --path apps/world --rendering-driver opengl3 --script capture_transparency_log.gd
```

The script printed `CAPTAINS_LOG_CAPTURE_PASSED`. The only error logged was the
container's missing ALSA audio device (`ERR_CANT_OPEN`). Desktop input is isolated
during the capture, so the script calls the world's key handler for **G** and the
log's key handler for `.` and **L**, and emits the pin's `pressed` signal for the
click. `test_captains_log.gd` exercises the same paths headlessly. Owner visual
acceptance is pending.
