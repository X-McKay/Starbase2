# Native interface polish evidence

Date: 2026-09-07. Local functional and visual checks for the
[interface pass](../../docs/world-ui.md); not a production qualification and not
an agent-quality comparison.

- `check-world-before.log`: the complete `just check-world` suite on the prior
  interface with Godot 4.7.2, establishing the baseline before changes.
- `check-world-after.log`: the same suite plus `test_ui.gd` after the changes.
- `before-inspect.png`: the prior inspector rendered from the same fixture on the
  same virtual display, for direct comparison with `inspect.png`. Earlier retained
  captures of the prior board and compact inspector are in
  [command-district](../command-district/findings-compact-final.png) and
  [building-catalog](../building-catalog/stale-compact.png).
- `normal.png`, `inspect.png`, `inspect-compact-large.png`, `directory-compact.png`,
  `help.png`, `board-evidence.png`, `board-repositories-compact.png`,
  `disconnected.png`, `reduced-motion-directory.png`: actual renders under Xvfb
  with Mesa software rendering, using the labelled synthetic
  [world fixture](../../fixtures/world/stale.json) and the retained synthetic
  [board fixture](../command-district/board-fixture.json). No live core, no
  dispatch. `disconnected.png` polls an unreachable loopback port.
- `*.png.json`: the capture metadata written by the client. Frame intervals are
  software-rendered process intervals on a shared container and are not a
  performance measurement.

Capture recipe (repository root; absolute fixture paths):

```sh
xvfb-run -a -s "-screen 0 1280x800x24" godot --path apps/world --max-fps 60 -- \
  --fixture="$PWD/fixtures/world/stale.json" \
  --capture="$PWD/evidence/world-ui/inspect.png" --frames=90 --inspect
```

Preserved failures are described in the design record; the first UI test run
that exposed the dock overflow and the un-rendered board assertion was not
retained as a log because it ran interactively, and its fixes are covered by
the retained passing suite.
