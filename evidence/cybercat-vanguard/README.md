# Vanguard comparison evidence

Source: exact user model `01a07ca6-670a-771d-ae60-08f7e669bfef`, shared at
<https://www.meshy.ai/s/GzLfrz>. The original has 31,087 triangles, 8K textures,
no skeleton and no clips. It was not regenerated.

The website task ID was rejected as rigging input with HTTP 400, without a task
being created. Passing its returned GLB URL through Meshy's documented model
input succeeded. Rig task: `01a07cc4-96db-7038-80e8-d8b5be949533` (5 credits,
walk and run included). Idle task: `01a07cc8-df2e-71f7-a169-f710655fa1c8`
(3 credits). Total project allocation: 208 of 250 credits.

`source-weights.json` records original upper-body weight distribution. The local
preparation uses the actual neck height to blend into a rigid helmet/face region
instead of retaining shoulder influence above the collar. Originals remain
unchanged in `meshy_output`. Shipping textures are bounded to 2K.

`cadence-first.log` verifies 6 m/s physical movement with a 2.8 m run stride,
plausible foot contacts and stop-to-idle. Native captures and a final rigid-head
audit follow the Blender preparation before player selection.

## Accepted source checks

`check-world.log` passes the complete scene/interaction suite and native command
fixture with Vanguard selected for the player. `helmet-audit.json` measures
15,565 fully rigid vertices at 25 poses in each of four clips; maximum deviation
is below 0.001 mm. The first audit also included partially blended neck vertices;
that check is retained, and the final audit explicitly selects fully rigid
weights while leaving the neck flexible. The export now explicitly limits skin
weights to four influences before both audit and GLB export.

`run-close.png` and `run-review.gif` show the native running model close up.
`engineering.png` records it in the current Engineering room. These are offline
visual fixtures. No character motion dispatches work or changes activity status.

The updated unsigned macOS package passed `just check-world-export` at
`.local/vanguard-review/Starbase2-macOS.zip`. Its `manifest.json` binds source,
executable and pack hashes; native colony and compact reduced-motion interior
captures passed. The extracted `.local/vanguard-playable` copy is opened at
Engineering with the offline stale fixture. The earlier offline review process
was replaced; no live backend work was dispatched. No commit or deployment made.
