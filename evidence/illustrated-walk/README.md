# Illustrated walk study

Status: raw draft retained; a cleaned derivative is now integrated for screen-right
travel. See [implementation and tests](integration/README.md).

The user supplied a frame-by-frame RPG sprite sheet and clarified that the desired
workflow is illustrated 2D sprite animation. The earlier 3D character style remains
rejected. The approved captain from `apps/world/art/crew-adventure.png` was the
identity/style reference; the user's attachment was a layout/motion reference.

Two built-in image-generation calls and their exact prompts are retained in
[prompts.json](prompts.json):

- `directional-draft.png`: 8×4 layout, 1586×992 RGB. Illustration matches the
  intended direction more closely, but many side poses scarcely change. Rejected
  as a complete walk cycle.
- `side-cycle.png`: 4×2 layout, 1774×887 RGB. One screen-right eight-pose study.
  Contact and passing silhouettes differ, but knee lift, arm opposition, repeated
  poses and loop rhythm still need art review and refinement.

Both files contain **painted checkerboard pixels**, not actual transparency.
Neither raw file passes the production alpha validator. This original study
performed no matte removal. The subsequent integration removes the boundary-connected
matte deterministically, retains these source files, and uses the resulting RGBA
derivative for screen-right travel.

`preview.gd` plays the eight raw cells in Godot at 7.5 frames/second. Per-frame
anchor metadata aligns the study without independently resizing poses. This
example preserves the backgrounds so its limitations remain visible. It makes
no backend requests and starts no operational work. This is a sheet-animation
proof, not a polished walking implementation.

[Native preview](preview.mp4) contains 192 frames at 30 FPS (6.4 seconds).
`frame-review.png` is a native still; `parse.log`, `preview.log`, `encode.log` and
`decode.log` retain validation. The AVI is local scratch under `.local`.

Reproduce from the project root:

```sh
godot --path apps/world --script "$PWD/evidence/illustrated-walk/preview.gd" \
  --fixed-fps 30 -- \
  --sheet="$PWD/evidence/illustrated-walk/side-cycle.png" \
  --capture="$PWD/evidence/illustrated-walk/frame-review.png"
```

Production completion still requires true cutout transparency, approved anatomy
and frame timing, consistent registration, four directional loops and normal/
compact native review. Additional idle/work/gesture clips can use the same sheet
pattern, but were not created in this study.
