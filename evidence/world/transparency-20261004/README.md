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

## Crew board and crew dialogue (slice 6)

Native captures of the [crew board and crew dialogue](../../../docs/crew-board.md),
same renderer and container. **All data is synthetic.** The stream replays
`fixtures/world/transparency/crew-board-stream.jsonl` (the slice 3 frames), paired
with `crew-board-v7.json` (mission 42 plus an invented accepted mission 41 with
PR #118) and `crew-board-world.json` (an invented repository review, repair trial
and watchkeeper records, one of which stopped changing six minutes before the
snapshot). Each frame is taken right after a fresh replay, so the badge reads
`[~] LIVE · … · SYNTHETIC REPLAY`.

| Image | Shows |
|---|---|
| `crew-board.png` (1440×900) | Tab board, nobody selected. Needs you: `Review PR #118 on algent` (Open PR), `Publish policy ends in 2d 14h` (Extend, not available here), `[?] Memory notes · not in these records` (Review in Field ops). Chips `[x] Next mission blocked: active_mission` and `[/] Wes silent 6 m`. Fourteen feed rows newest first. One line per crew member, Moss's day as duty officer. |
| `crew-board-filtered.png` (1440×900) | Rivet selected: feed shows Rivet only (`Show all crew ×`), Rivet's day `[>] Running tests · mission 42, round 2`, up next `Hand round 2 to Core for testing`, done in the last 24 h, `3.1k tokens observed this session`, `Talk to Rivet [T]`. |
| `crew-dialogue.png` (1440×900) | Rivet answers "Why can't we start another mission?": "Core refused admission with active_mission. Rivet is still on mission 42, implementing, round 2…" with `Based on: admission active_mission · mission sdlc-42 state implementing · /v7 snapshot 1 s ago`. The board behind is dimmed. |
| `crew-dialogue-stale.png` (1440×900) | Wes selected; Moss answers for him ("answering for Wes (silent 6 m · last known)") to "Is everyone accounted for?": "Not Wes. Nothing from the watchkeeper has changed in 6 m…", with the record id and last update time in `Based on:`. |
| `crew-board-compact.png` (960×700) | The board under the compact navigation: chips wrap, the feed and the day scroll, Talk and Watch stay on screen. |

`captures.json` holds these under `crew_board`: needs, chips, feed, crew lines, the
day panel, and the dialogue speaker, line and `Based on:` text per image.

```sh
xvfb-run -a -s "-screen 0 1440x900x24" godot --path apps/world --rendering-driver opengl3 --script capture_transparency_board.gd
```

It printed `CREW_BOARD_CAPTURE_PASSED`; the only error logged was the missing ALSA
device (`ERR_CANT_OPEN`). Review notes: the board panel is translucent, so world
geometry shows faintly behind it; crew lines truncate at 960 px with the full text
in tooltips. Owner visual acceptance is pending.
