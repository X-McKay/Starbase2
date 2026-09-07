# Expanded colony layout checks

2026-09-07. User requested comfortable larger structures and more space. Four
footprints are now Command/Training 16 × 12 m, Habitat 18 × 13 m and Botanical
17 × 12 m. Their placement origins are `(-3,-21)`, `(1.5,3)`, `(36,-15)` and
`(30,30)`. Engineering and the landing pad retain their prior placement.
The east/south shelf coordinates expand by 12%; movement speed and zoom controls
are preserved. Foundations still require three metres between structures and
roads remain two 1.5-metre tiles wide.

Headless checks passed with exit 0 and no logged errors:

- [Shelf shape/headlands](shelf-shape.log).
- [Connected orthogonal paths](test_paths-initial.log).
- [Navigation](test_navigation-initial.log).
- [Decorative environment and reduced motion](test_environment-initial.log).
- [Coast collision/return journeys](test_coast-initial.log).
- [Uplands seam](test_uplands-initial.log).
- [Movement, zoom and exploration](test_exploration-initial.log).
- [Paving after the correction below](test_paving-corrected.log): 1,252 tiles.

The [first paving failure](test_paving-initial.log) exposed a real overlap between
one Habitat foundation tile at `(45,-28.5)` and the relocated spring footprint.
The spring/ring and its shared collider moved together to centre `(54,-34)`;
the collider is `Rect2(48,-39,12,10)`. The unchanged paving test then passed.
No collision, spacing, street-width or test thresholds were relaxed.

These checks ran after authored architecture enlargement, while remaining
generated hull/prop connections were still being assembled. They qualify the
layout slice, not the eventual final build. Full interior journeys, native
visual review and standalone export qualification remain with the parent task.
