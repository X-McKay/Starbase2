# Inhabited polish

This user-approved milestone follows the qualified living-colony final-03
baseline (525 world files). It gives the Habitat a more legible domestic
interior, adds restrained environmental motion, and extends the selected
Vanguard with upper-hair secondary motion and surface-aware footfalls.
All four authored interiors are rebuilt through the existing structure builder.
Engineering's original production assets and the original Vanguard source and
runtime model are retained.

The built-in ImageGen reference and exact prompt are retained in
`concepts/habitat-living.png` and `concepts/prompt.txt`. The concept is design
reference, not an implemented screenshot. One Meshy sofa was selected after
the image-review gate. It is a straight sage upholstered sofa, replacing the
concept's sectional with a bounded object suitable for the actual room.

## Generation and editable sources

The new allowance is 1,000 Meshy credits, with zero prior charges applied to
this allowance. Historical spending of 507 credits is excluded. The sofa image
cost 9 and the mesh cost 30: actual total 39, pending reservations 0, remaining
961. No additional paid calls are planned. `plan.json` and the separate
`meshy_output/inhabited-polish-ledger.json` govern generation; the reporter
copies only sanitized stage identifiers, charges and local original paths.
It does not dispatch or write the ledger.

The sofa retains the original downloaded GLB, editable packed Blender source,
and normalized runtime GLB under the corresponding `habitat-lounge-sofa`
directories. The source has 13,406 triangles. Its four 2k texture images and
exported base-color, normal, metallic/roughness and emission bindings are
recorded in the prop provenance. Blender reported a shared-texture-sampler
warning; recorded channel bindings are present. Final native appearance has
been reviewed, while exact sampling equivalence remains unproven. This warning is not represented
as a clean export or as proof that textures were lost.

The fan assembly is authored offline in Blender, with separate editable source
and runtime output under `environment/colony-vent`; it spends no generation
credits. Water and fan motion are cosmetic and obey reduced motion. Footfalls
are driven by real displacement, distinguish metal/wood/soil, and start muted.
Upper loose hair receives a bounded spring; the rigid helmet and original
source geometry remain intact. Lower hair is not simulated. Audio has not
received human audition.

## Rebuild and preservation

Run `mise exec -- just world-inhabited-build` with the pinned Blender 5.2.1
installation and retained original inputs available. The recipe prepares the
secondary-motion character and sofa, rebuilds the four interiors and fan,
connects structures, then imports Godot assets. It makes no paid calls. This is
an offline rebuild recipe, not a promise of byte-identical Blender exports or
automatic art approval.

Run `python3 assets-production/batches/inhabited-polish/record_provenance.py`
after sources and imports settle. It snapshots world sources, media and import
sidecars (excluding generated `.godot` cache), selected production trees,
original sofa files and historical provenance dependencies. It compares the
prior 525-file world baseline and the older 96-file preservation set. Of those
96, 94 remain unchanged; the two intentionally changed files are
`characters/model_visual.gd` and `characters/definitions/operator.tres` under
`apps/world`, implementing and selecting the new character variant. Unexpected
changes fail the reporter. The original character GLB and Blender source are
preserved. Earlier milestone provenance remains an immutable historical
description, rather than being rewritten to claim the current world is old.

Final focused structure, inhabited-journey and living-colony tests passed.
`mise exec -- just check-world` and `mise exec -- just check` passed sequentially.
The final native four-room journey passed with 16 room/interaction frames and
12 motion frames; all 553 world files matched its launch snapshot. The sofa
faces inward, with its rear/profile partly occluded by the east wall. No evident
furniture intersection or detached fan was found in that review. Exported PBR
channels and native appearance have been inspected; exact sampler equivalence
and human audio audition are not established.

Final frozen-source standalone export `20260908-final-01` qualified with clean
exit 0 and all 553 world files matching. The durable manifest, logs and exported
PNGs are in `evidence/world/inhabited-polish/final/package-01/`. The local archive
is `.local/reviews/inhabited-polish/20260908-final-01/Starbase2-macOS.zip`;
the extracted playable executable and PCK hashes match the manifest. Root review
of exported Habitat and water found the intended sofa orientation/materials,
fan mount and spring appearance. Sidewall occlusion remains visible.

This is local unsigned macOS qualification, not deployment or owner art
acceptance. Human audio audition remains open. The evidence directory records
failures and subsequent diagnosis separately.
