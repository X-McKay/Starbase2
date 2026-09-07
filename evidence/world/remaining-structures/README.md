# Remaining structures local production review

2026-09-07, branch `feature/remaining-structures`, based on `a53f572`.
This is a local visual and gameplay milestone; nothing was published or deployed.

## Delivered composition

| Structure | Exterior | Furnished interior | Room footprint |
|---|---|---|---|
| Command (`review`) | Observation bridge, communications crown | Mission table, four analysis desks, seating and storage | 16 × 12 m |
| Training (`gym`) | Paired vaults with violet service channels | Two simulators, two resistance stations and lockers | 16 × 12 m |
| Habitat (`habitat`) | Rounded living pods with amber windows | Three sleep capsules, galley, dining and lounge furniture | 18 × 13 m |
| Botanical (`greenhouse`) | Ribbed conservatory and water tower | Four planted racks, laboratory bench and water services | 17 × 12 m |

The eastern and southern plateau coordinates expand by 12%. Habitat and Botanical
move farther apart; paving and protected landmarks follow the new layout.
Engineering and character preservation was checked against 96 baseline hashes.
Backend identities, movement speed and zoom controls remain unchanged.

## Production and recovery

Built-in image generation produced four architecture concept plates. Meshy made
four fitted hulls and nine distinct equipment assets. Blender retains editable
architecture, prepared hulls and props; Godot owns physical walls, exact doorways,
furniture collision, anchors and cutaways.

Sources are under `assets-production/structures/{command,training,habitat,botanical}`
and `assets-production/props/`. Runtime media use the matching categories and IDs
under `apps/world/assets/`; composed scenes are under `apps/world/structures/`.
The selected files are catalogued with hashes in the
[batch provenance](../../../assets-production/batches/remaining-structures/provenance.json).

`mise exec -- just world-remaining-build` rebuilds selected assets without paid
calls. The complete successful run is retained in
[final-rebuild.log](assembly/final-rebuild.log). Original paid downloads and the
reconciliation ledger in ignored `meshy_output/` must remain available for rebuilds.
Keep that input directory and hydrated Git LFS sources when moving the workspace.

Meshy accounting: **507 actual credits, 0 pending, 743 remaining** of the new
1,250-credit allowance. Historical 208-credit work is separate. See
[accounting](../../../assets-production/batches/remaining-structures/ACCOUNTING.md).

## Evidence and qualification

Baseline results, CI status and preservation hashes are under `baseline/`.
The representative Command iterations are retained in `command/`, `command-v2/`
and `command-v3/`; the first plain template was superseded after visual review.
Layout test failures and the protected spring correction remain under `layout/`.

The full suite also caught a scenery-clearance violation beside Botanical's
new feeder path; the shared outcrop moved from (12, 35) to (10, 42). Historical
spring and cliff test probes were updated to the current shared geometry so
they continue checking the intended protected surfaces. Failed runs are retained
beside corrected verification logs.

All four final native exteriors and cutaways are in [final/native](final/native/).
Native capture completed without engine errors using an offline stale fixture.
Focused physical contact and five approach/interior/console/exit journeys passed;
their logs are in [final/logs](final/logs/).

`mise exec -- just check-world` passed in
[check-world-final.log](final/logs/check-world-final.log). The repository suite
passed in [check-corrected.log](final/logs/check-corrected.log): 34 Rust tests,
76 Python tests, lint/type/contract checks and 100 Markdown/12 requirement checks.
The full world suite preceded the capture-only RGB8 conversion fix below; the
fresh standalone qualification exercises that final capture source.

The first export correctly failed on motion-contact-sheet image-format errors
after its journeys ran. The capture code now converts frames to RGB8. The fresh
[unsigned macOS review archive](../../../.local/reviews/remaining-structures/20260907-final-02/Starbase2-macOS.zip)
**passed standalone qualification**, including all native journeys with clean
stderr, exterior/interior captures and a nonblank 12-frame motion contact sheet.
The actual [Command interior](final/package-02/review-interior.png),
[Botanical interior](final/package-02/greenhouse-interior.png) and
[motion strip](final/package-02/review-motion.png) were inspected. Logs, captures
and JSON reports are retained under [package-02](final/package-02/).
The [manifest](final/package-02/manifest.json)
binds the exact source, executable and archive hashes. Archive SHA-256:
`219af1b38bbb9461be9e0952df8bddd2adac8ae3193ac88d71adbc206cdcf4c0`.
Final source hashes were reverified with zero mismatches. The extracted playable
review was opened offline in Command. The local archive requires this workspace; they are not a deployment or an
owner art approval.

## Visual limits and follow-up conditions

Owner art acceptance remains open. Botanical glazing and Command windows are
textured surfaces, not transparent views into furnished rooms. Generated hulls
are fitted nonuniformly to exact playable architecture; the transform factors
and doorway face removal are recorded per hull. Interiors use shared authored
wall and floor modules with room-specific generated equipment and generous aisles.
No performance improvement is claimed.

If owner review calls for translucent glazing or denser interior dressing, the
asset-production owner should revise the relevant Blender source/materials,
repeat exterior and cutaway inspection plus physical journeys, then qualify a
fresh export. The current captures are evidence of the actual local build, not
claims of exact reproduction of the concept paintings.
