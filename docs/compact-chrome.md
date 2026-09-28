# Compact exploration chrome

Status: proposed

At 800×640, the horizontal navigation now starts below the measured masthead
instead of sharing its subtitle row. The room guide and other compact workspaces
start below navigation. A dark navigation background preserves contrast over
bright habitat scenery. The HUD collapse/restore label and F1 shortcut remain
fully visible with larger text.

Crew cards use concise labels when horizontal space is constrained: **Between
tasks**, **State unknown**, **Last known**, and **Route blocked** where applicable.
These are projections of the existing status, not new task states. Keyboard focus
or pointer hover displays the full derived status below the cards; the tooltip
retains that status and duty text. Enter still opens the same crew dossier and
retained work. The strip reserves its measured height and bottom safe margin.
No activity, freshness, authority, task result or animation semantics changed.

`test_compact_chrome.gd` reproduces the old collision and clipped text, then checks
header/navigation/guide separation, full control/card text, navigation contrast,
keyboard full-status access and the bottom margin at normal and larger text.
Existing contextual HUD, HUD polish, console HUD, Joint and Practice checks pass.
Native habitat and guide captures use the existing closer-camera test without
changing camera behavior. [Before/after evidence](../evidence/world/compact-chrome-20260928/README.md)
retains the failed reproduction, intermediate contrast finding and final captures.

This is a narrow client layout correction, not a claim of full screen-reader
coverage, measured performance improvement or owner art acceptance. Parent release
verification owns the packaged artifact. Reverting the HUD/strip layout changes
does not change retained Core work or command behavior.
