# Engineering review build

Status: implemented for owner review; expansion to other bespoke interiors waits
for this review. Branch: `feature/meshy-blender`. No commit or deployment made.

The owner approved **250 Meshy credits**. This batch consumed **140 credits**:
Including the earlier 60-credit batch, recorded generation totals **200 / 250**,
leaving **50 credits**. This pass included
three design images, three image-to-3D models, three remeshes, three PBR textures,
one character rig and one idle animation. Walk and run came with rigging. The
console gesture was authored and baked locally in Blender. Task IDs, per-stage
charges, triangle counts and asset hashes are in [provenance.json](provenance.json).

The built-in image tool produced [concept v1](../../structures/engineering/concepts/concept-v1.png). Meshy received it
as an image reference for the three isolated designs in `references/`. The
cooling-module design produced a complete hull, which was selected as the
Engineering exterior. These are newly generated assets inspired by the owner's
reactor reference, not a download of that exact shared model.

## Playable slice

Walk or click through Engineering's sliding airlock. The hull fades to reveal an
authored service room with a detailed containment reactor, PBR materials, copper
services, deck panels, lockers, consoles, warm task lights and restrained cyan
machinery. The retained shadow roof keeps the interior shaded during cutaway.

The player and Mender share the new 1.85 m engineer rig, with distinct tints.
Actual player displacement selects walk or run; stopping blends to idle. Opening
Mender's inspection panel while in Engineering enables a local console gesture.
This is cosmetic: it never asserts that an agent is doing work. Authoritative
unknown/stale/failed labels remain visible. Other crew retain the repaired
Cybercat model. Portraits and the structured inspection path remain available.

Reduced motion freezes reactor effects and skeletal movement. Reactor ambience
is positional and defaults off. Existing faster travel, zoom controls and the
expanded plateau remain in the build.

## Review evidence and limits

Native exterior, interior, reduced-motion and animation captures are under
`evidence/engineering-polish`. The helmet audit sampled 25 poses in each of four
clips: 1,741 repaired rigid vertices stayed within 0.001 mm in head space. This
measures the rigid region; the collar, silhouette and limbs also need visual
judgment. Generated hard-surface geometry retains some soft/beveled AI detail;
the concept is art direction, not an exact screenshot target.

Focused checks cover PBR channel retention, room access, muted audio, reduced
motion, inspection gesture scope, four clips and no backend dispatch. The world
suite exercises all five continuous journeys, collisions, keyboard inspection,
offline states and native command reconciliation. Review should judge the
exterior silhouette, interior density, character scale and motion together
before extending this pipeline to the rest of the colony.

## Rebuild and rollback

Run `mise exec -- just world-engineering-build` with Blender 5.2.1 installed. It
uses retained downloads and performs no paid generation. The editable `.blend`
files and scripts are here; original Meshy downloads remain in `meshy_output/`.
`world-colony-build` reapplies the polished Engineering connection after rebuilding
the shared colony. Godot 4.7.2 imports the GLBs and textures.

To revert this slice while retaining the earlier continuous colony, reconnect
`repair-continuous.tscn` using `assets-production/scripts/connect_colony.py` and restore the
previous character definitions from the working diff. This is a local world-art
change with no database migration or backend deployment.

The final unsigned macOS package passed standalone qualification at
`.local/engineering-polish-qualified/Starbase2-macOS.zip`. Its `manifest.json`
records the exact source and artifact hashes. The running offline review uses
the extracted copy in `.local/engineering-polish-playable` and starts in
Engineering. Use WASD/arrows or click to travel, +/− or the HUD zoom buttons,
E to inspect and F to return to the colony. Native captures and the animation
loop are available in `evidence/engineering-polish`.


Follow-up: the player now uses [CyberCat Vanguard](../../characters/cybercat-vanguard/README.md),
while Mender keeps the Engineering suit. The original package above remains the
pre-Vanguard baseline. Vanguard adds 8 credits, bringing recorded total spend
to 208 / 250, with 42 remaining.
