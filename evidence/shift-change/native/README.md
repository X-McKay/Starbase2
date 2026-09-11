# Shift Change native rehearsal

Godot 4.7.2, native Metal compatibility renderer, Apple M5, 1440 × 900.
Both invocations used explicit offline world/board fixtures and input isolation.
Initial actors were staged one metre from authored anchors; every subsequent
movement used actual crew physics/navigation and the shipped rig animations.
No production snapshot requests or commands were issued. This is visual and
physical fixture evidence, not a production job or provider acceptance run.

- `domestic-01`: passed in 7.869 seconds; 11 PNGs. The Reviewer reached the
  authored Habitat seat, entered `social/seated`, used `social/stand_up` on
  assignment, and exposed fast completion evidence without visiting a station.
- `journey-01`: passed in 95.071 seconds; 15 PNGs. Reviewer left the Habitat seat,
  reached the real Survey Command workstation at 49.989 seconds, displayed
  terminal evidence at 50.231 seconds before returning, and physically reached
  the home seat at 94.189 seconds. Brief-job redirect, offline hold, and reconnect
  coalescing passed. No blocked route occurred.
- `verification.json`: the release helper `verify_shift_report` checked report
  gates, transition samples, complete PNG sequences and hashes for both runs.

The strongest composition view is
[occupied Habitat](domestic-01/domestic-occupied-habitat.png).
[Console arrival](journey-01/journey-console-arrival.png) and
[return home](journey-01/journey-home.png) show the physical round trip.
Seated and stand-up sequence frames are actual rendered poses, not generated
images or staged replacements. No movie encoder was available on PATH, so the
native PNG sequences are retained directly.

Visual judgment: the timber floor, pale teal-edged rug, central Meshy sofa,
pendants and warm pod lights establish a legible inhabited lounge. Crew remain
visually distinct in this lighting, though the original armor textures are still
dark and metallic-looking in their baked colors. No obvious seated mesh clipping
is visible at normal room scale; separate close-up animation evidence records
the rig-specific seat correction. The return-home camera was still easing after
30 frames, cropping the far edge; the initial domestic view shows the complete
composition. The capture harness now waits 120 physics frames at both room
transitions; the final [package qualification](../README.md) verified that framing correction.
These earlier passing captures retain their original 30-frame limitation.
Console activity remains the existing standing console pose rather
than a newly authored hand-contact animation.

Timing samples include PNG capture/render work and are not a gameplay benchmark.
Domestic median/p95: 17.286/255.032 ms; journey rolling median/p95:
16.772/20.436 ms. These numbers do not establish a performance improvement.

Reproduce each bounded run from the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path apps/world \
  --resolution 1440x900 --max-fps 60 --log-file /private/tmp/shift-change.log -- \
  --fixture=/Users/al/git/Starbase2/fixtures/world/stale.json \
  --shift-change-capture=/private/tmp/shift-change-domestic --shift-change-mode=domestic
```

Use a fresh output directory and `--shift-change-mode=journey` for the physical
round trip. Capture calls force one render only inside the explicit fixture
harness, avoiding background-window `frame_post_draw` stalls. The harness has a
175-second working bound and a 179-second watchdog; normal gameplay is unchanged.
