# CyberCat Vanguard player

Exact user-supplied source: <https://www.meshy.ai/s/GzLfrz>.
Source task: `01a07ca6-670a-771d-ae60-08f7e669bfef`.
The shared page calls it “Cyber Kitty Vanguard”; task metadata calls it
“CyberCat Vanguard”. The original GLB has 31,087 triangles and 8K textures,
with no skin or animation clips. It is retained in `meshy_output`.

The completed comparison added a Meshy rig (5 credits, including walk/run) and
idle (3 credits). The shared rig-preparation script keeps the original file,
rigidly binds the helmet/face region, bounds game textures to 2K, and adds the
locally authored console clip. Native close-up review and the rigid-head audit passed; Vanguard is selected
for the player. Mender retains the Engineering suit.

Rebuild with `mise exec -- just world-vanguard-build`. This reuses saved Meshy
exports and does not generate new paid tasks. No backend state or permissions
are associated with this cosmetic model.

The game GLB is approximately 8.4 MB, retaining the original 31,087-triangle
shape at 1.85 m. Walk uses a 1.6 m stride and run a 2.8 m stride, both driven by
actual movement; the 6 m/s cadence and stop-to-idle checks pass. The rigid-head
audit samples 100 poses across four clips and excludes the intentionally flexible
neck blend. Source models and clips remain unchanged. See `provenance.json` for
exact hashes, task IDs and sizes. Total recorded credit use is 208 / 250.

The final standalone macOS qualification passed. Review package:
`.local/vanguard-review/Starbase2-macOS.zip` (unsigned local build), with captures,
logs and exact hashes alongside it. The offline playable copy is under
`.local/vanguard-playable`.
