# World asset sources and repurposing pipeline

Status: draft

Where to find high-quality, free 3D models for the Starbase2 world, how to get
them into Blender, and how they reach Godot. This is a homelab project, so the
decision to repurpose fan-made and game-extracted assets from licensed
franchises is accepted for private builds. That decision has two hard
consequences that keep [experience.md](experience.md)'s "original assets with
provenance" rule honest:

- Every imported asset carries a provenance record (source URL, original
  creator, upstream game if extracted, date, license as stated by the source,
  and the modifications made). See [Provenance manifest](#provenance-manifest).
- Assets whose provenance is a game rip or an unlicensed fan port are tagged
  `private-only` and must never ship in a public release, demo build, screenshot
  set intended for publication, or the repository itself. Keep them in the
  asset store outside git (see [Storage](#storage)).

Page-level details below (triangle counts, exact license strings, whether a
download is still live) were not verifiable from the sandbox that wrote this
document: Steam Community, Sketchfab, DeviantArt, BlendSwap, and The Models
Resource are blocked from it. Confirm each item at download time and record
what you actually got in the manifest.

## What the art direction actually needs

[experience.md](experience.md) proposes an orthographic 3D environment with
restrained geometry and expressive billboard/sprite characters. That changes how
sourced models get used:

- **Characters as sprite sources.** Full game-rig characters (Goku, Master
  Chief, a stormtrooper) are most useful rendered from Blender into
  8-direction billboard sprite sheets, not dropped into the scene as
  50k-triangle skinned meshes. Blender's orthographic camera plus a Mixamo or
  in-game animation set gives idle, walk, sit, and work loops cheaply.
- **Vehicles and props as real meshes.** Ships (X-wing, Pelican, Warthog,
  capsule pods) and set dressing suit the orthographic 3D scene directly after
  decimation and a material bake to one albedo plus one ORM texture.
- **Poly and texture budgets.** Target under 10k triangles per prop and one
  2k texture set per hero prop until the first art spike measures frame time
  on the reference hardware. Game rips usually arrive at 3 to 10 times that
  and need Blender's Decimate or a manual retopo pass.

## Sources by franchise

Preference order for each franchise: community-authored downloadable models on
Sketchfab or BlendSwap (clean licenses, already in FBX/glTF/blend), then
community ports on DeviantArt/XNALara/SFM Workshop (rigged, but Source or XPS
formats), then extracting from a game you own (best fidelity, most work).

### Dragon Ball

| Source | What it offers | Format and notes |
|---|---|---|
| [Sketchfab "dragon ball" collection by z.faizz](https://sketchfab.com/z.faizz/collections/dragon-ball-d7041a68a3324894a448d3979aa77d9f) | Rigged Vegeta, Goku Black, Vegito, Gogeta and others gathered in one collection | Sketchfab download gives glTF/USDZ plus source; check each model's CC license |
| [Rigged Goku by shamus](https://sketchfab.com/3d-models/rigged-goku-ssj5-dragon-ball-af-b6808c70f790454fafc3d6227c7ad445) and [Vegeta by Tigerar1](https://sketchfab.com/3d-models/dragon-ball-z-vegeta-1c2513a9957a4072a505ce9100da19dd) | Individual rigged characters found via the `goku` and `dragonball` tags | Same as above |
| [Sparking! ZERO Goku FBX by NekoPixil (DeviantArt)](https://www.deviantart.com/nekopixil/art/FBX-Goku-DB-Sparking-ZERO-3D-Model-DL-1108604555) | Extracted from the 2024 game in PSK and FBX, reported to include in-game animations | FBX imports straight into Blender 4.x; the cel-shaded look needs a toon material rebuilt |
| [Kakarot Goku (XPS) by MrUncleBingo](https://www.deviantart.com/mrunclebingo/art/Dragon-Ball-Z-Kakarot-Son-Goku-Default-827671835), [HiGuys920's Kakarot and Xenoverse 2 ports](https://www.deviantart.com/higuys920/art/DBZ-Kakarot-Beerus-Planet-Stage-XPS-888987901), [Xnalara-Customized DBZ gallery](https://www.deviantart.com/xnalara-customized/gallery/70937414/dbz) | Characters and full stages ported from DBZ: Kakarot and Xenoverse 2 with original bones | XPS format; import with the Blender 4.x XPS add-on below |
| [Kakarot Goku SFM model (Workshop 2087768713)](https://steamcommunity.com/sharedfiles/filedetails/?id=2087768713) and [gmod dragon ball items (Workshop 2976035482)](https://steamcommunity.com/sharedfiles/filedetails/?id=2976035482) | Source Filmmaker and Garry's Mod ports with Valve-biped bones, face flexes, and bodygroups | GMA/MDL; extract with the Source pipeline below |
| [The Models Resource: Dragon Ball FighterZ](https://models.spriters-resource.com/pc_computer/dragonballfighterz/) | Community-uploaded FighterZ rips | Coverage is thin; FighterZ meshes need heavy cleanup after import |
| Extract from Sparking! ZERO yourself: [FModel tutorial on GameBanana](https://gamebanana.com/tuts/18330) | Every character, stage, and animation at source quality | UE 5.1; export meshes as `.uemodel` and armatures as `.psk`, import with the UEFormat and PSK Blender plugins; requires owning the game |

### Halo

| Source | What it offers | Format and notes |
|---|---|---|
| [Sketchfab "Halo for FREE" collection by PiedroNZ](https://sketchfab.com/PiedroNZ/collections/halo-for-free-58c37e7d0e424adcbb1979552f75426a) | Curated free Spartans, Master Chief variants, and vehicles | Per-model CC licenses |
| [Halo Infinite Master Chief Rigged by bizarrefog1](https://sketchfab.com/3d-models/halo-infinite-master-chief-rigged-0ad7b1431a6748959d691e9c171c6e2c) and [Halo 5 Master Chief by jameslucino117](https://sketchfab.com/3d-models/charactershalo-5spartansmaster-chief-57be126df72d48859686ae5382e3c4d1) | Rigged Chief models from the two most recent art styles | Sketchfab download |
| [Halo Warthog by pinto36](https://sketchfab.com/3d-models/halo-warthog-bd3403bc06884260ac31d0e98eed81e4) | Warthog blending the Halo 1 to 3 designs; a natural mechanical-courier stand-in | Sketchfab download |
| [Halo Infinite Master Chief (Workshop 2678089924)](https://steamcommunity.com/sharedfiles/filedetails/?id=2678089924) | Infinite assets ported to Source | GMA/MDL; Source pipeline below |
| [Master Chief (Halo Infinite) MMD by SAB64](https://www.deviantart.com/sab64/art/MMD-Model-Master-Chief-Halo-Infinite-Download-965364356) | Infinite rip converted to MikuMikuDance | PMX; Blender's `mmd_tools` imports it |
| Extract from Halo: The Master Chief Collection yourself: [Reclaimer](https://github.com/Gravemind2401/Reclaimer.Architect), [CR4B Tool](https://github.com/PlasteredCrab/Halo-CR4B-Tool), [Foundry](https://github.com/ILoveAGoodCrisp/Foundry), [Halo asset Blender toolset](https://github.com/general-101/halo-asset-blender-development-toolset), [VG Resource MCC extraction tutorial](https://archive.vg-resource.com/archive/index.php/thread-38349.html) | Every Halo 1 to Reach character, vehicle, weapon, and level at source quality with correct shaders | CR4B fully supports Halo 3 and ODST and needs the H3EK tags folder; Foundry covers Reach, Halo 4, and H2A MP; requires owning MCC and the mod tools |

### Star Wars

| Source | What it offers | Format and notes |
|---|---|---|
| [BlendSwap Star Wars category](https://blendswap.com/3d/star-wars) | Roughly 240 community `.blend` files under Creative Commons | Already Blender-native; the cleanest license story of any source here; free account required |
| [Sketchfab "Star Wars Downloadable Assets" by dergreif](https://sketchfab.com/dergreif/collections/star-wars-downloadable-assets-d92d41b214ea460d81c90a7caa8ee0d8) and [Tsek11's Blender-oriented collection](https://sketchfab.com/Tsek11/collections/star-wars-models-for-blender-0647877eac8040ac87acb3ccd4828077) | Curated downloadable, textured stormtroopers, Mandalorian armor, ships | Per-model CC licenses |
| [X-wing by Heataker](https://sketchfab.com/3d-models/star-wars-x-wing-fighter-e6b85951f85940c1b26505eda7d73ef9), [X-wing by DanielAndersson](https://sketchfab.com/3d-models/star-wars-x-wing-a93f607a94d747568371b8910a81fb12), [Millennium Falcon by Quiznos323](https://sketchfab.com/3d-models/millennium-falcon-star-wars-ed6dc932c3ce407dbe4b903c73595030), [ships collection by lolface9](https://sketchfab.com/lolface9/collections/star-wars-ships-f62b4c97f70d4b2e96f577cea3c3165b), [ships and vehicles by FowlerJ98](https://sketchfab.com/FowlerJ98/collections/star-wars-ships-and-vehicles-b99177fc30d14384a8dc11591558ad5a) | Hero ships and a Falcon cockpit interior suitable for the mobile research vessel prototype | Sketchfab download |
| [Battlefront II ports by BlinkJisooXPS](https://www.deviantart.com/blinkjisooxps/art/Battlefront-2-Obi-Wan-Kenobi-781710818), [XNALara Star Wars thread](http://www.xnalara.org/viewtopic.php?t=72), [SFMLab Battlefront II pack](https://sfmlab.com/project/279eda1c-9029-4be5-baac-011cebbd6256/) | Battlefront II (2017) characters: Obi-Wan, Anakin, Maul, Yoda, Palpatine, Rey, Jyn, clones | XPS or SFM formats; the highest-fidelity Star Wars characters available without extracting |
| [Star Wars Collection for SFM (Workshop 1928312834)](https://steamcommunity.com/sharedfiles/filedetails/?id=1928312834) and [Star Wars Models (Workshop 1889865172)](https://steamcommunity.com/sharedfiles/filedetails/?id=1889865172) | Large Source ports of Battlefront II assets | GMA/MDL; Source pipeline below |
| [The Models Resource: The Force Unleashed (PC)](https://models.spriters-resource.com/pc_computer/starwarstheforceunleashed/) | Older but complete, lower-poly characters and props | Already close to the poly budget |
| Extract from Battlefront II (2017) yourself: [Frosty Editor tutorial](https://falloutug.net/f4/forums/porting/porting-tutorials/extracting-swbf2-2017-assets-with-frostyeditor); from Jedi: Fallen Order or Survivor: umodel/FModel | Source-quality characters, vehicles, and full environments | Requires owning the game |

### The Garry's Mod workshop example

The user-provided example is
[Workshop item 2024393711](https://steamcommunity.com/sharedfiles/filedetails/?id=2024393711).
It could not be opened from the sandbox, so its title, author, and contents are
not recorded here. Add them to the manifest when it is downloaded. Whatever it
is, a GMod workshop item follows the Source pipeline below.

## Original and CC0 alternatives

These fit the "original assets with provenance" rule directly and can ship in
public builds. Use them for the bulk of the world and reserve franchise assets
for crew personalities and hero props.

- [Quaternius](https://quaternius.com/): CC0 packs in glTF, including the
  [Modular Sci-Fi MegaKit](https://quaternius.com/packs/modularscifimegakit.html)
  (also on the [Godot Asset Store](https://store.godotengine.org/asset/quaternius/modular-sci-fi-megakit/)),
  [Sci-Fi Essentials Kit](https://quaternius.com/packs/scifiessentialskit.html),
  [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html),
  and the [Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html).
  A strong first candidate for the floating industrial terrace itself.
- [Kenney](https://kenney.nl/assets): CC0 low-poly kits, glTF included.
- [Mixamo](https://www.mixamo.com/): free auto-rigging and a large animation
  library for humanoid meshes, including the franchise characters above once
  they are cleaned. Godot 4 retargets Mixamo rigs through its humanoid bone
  map ([Godot4-MixamoLibraries](https://github.com/prfiredragon/Godot4-MixamoLibraries),
  [MixaBridge](https://mixabridge.uzair.gt.tc/)).

## Getting each format into Blender

Pin Blender to one 4.x release for the project and record it in the manifest.

| Arrives as | Tool | Notes |
|---|---|---|
| Sketchfab download | Blender glTF importer (built in) | Prefer the glTF download over "source" unless the source is `.blend` |
| BlendSwap `.blend` | Open directly | Check the Blender version the file was saved with |
| Garry's Mod `.gma` | `gmad.exe` from the GMod install, then [Crowbar](https://github.com/ZeqMacaw/Crowbar/releases) to decompile `.mdl` to SMD/DMX/QC, then [Blender Source Tools](http://steamreview.org/BlenderSourceTools/) | Keep every sibling file (`.vvd`, `.vtx`, `.phy`) next to the `.mdl` or Crowbar fails; convert `.vtf` textures with VTFEdit. [Guide: Exporting GMod addons to Blender](https://steamcommunity.com/sharedfiles/filedetails/?id=2964795518) |
| SFM Workshop | Same as GMod, skipping the `.gma` step | |
| XPS / XNALara `.xps`, `.mesh`, `.ascii` | [XNALara-io-Tools (Blender 4.x port)](https://github.com/Julz876/XNALara-io-Tools) or the [io-xnalara extension](https://extensions.blender.org/add-ons/io-xnalara/) | Imports armature and materials |
| MMD `.pmx` | `mmd_tools` add-on | Rigs use MMD bone names; rename before Mixamo |
| Unreal `.psk`/`.uemodel` | PSK plugin plus UEFormat plugin | For Sparking! ZERO, Kakarot, Jedi games |
| Halo tags | CR4B, Foundry, or Reclaimer export | See the Halo table |

Cleanup checklist before an asset leaves Blender:

1. Apply transforms, set scale to meters, and leave Blender's Z-up alone; the
   glTF exporter converts to Godot's Y-up.
2. Merge material slots, bake to one albedo plus one ORM texture at 2k or
   lower, and drop Source or Unreal shader specifics.
3. Decimate or retopo to the poly budget; keep the original in the asset store.
4. For characters headed to sprites: retarget to Mixamo or Quaternius
   animations, render 8 directions per animation with an orthographic camera,
   and pack sheets with the same pixel-per-meter ratio across all crew.
5. Rename bones to the Godot humanoid profile if the skinned mesh is kept.

## Getting Blender output into Godot

Godot 4's importer is built around glTF 2.0 and parses `.glb` natively with
skeletons, morph targets, multiple animations, and PBR materials. Export from
Blender as glTF 2.0 with NLA strips enabled so each animation becomes a named
clip. Godot 4.3 added a native ufbx-based FBX importer
([announcement](https://godotengine.org/article/introducing-the-improved-ufbx-importer-in-godot-4-3/)),
so raw FBX from DeviantArt or Mixamo also imports without conversion, but keep
glTF as the checked-in format. Set shared animation files to "Import As:
Animation Library" in the Import dock and assign the library to the crew's
`AnimationPlayer`.

## Storage

Model binaries, textures, and sprite sheets do not belong in this repository.
Keep them in a homelab asset store (a NAS share or a MinIO bucket on Kubani)
with the same top-level layout as `apps/world/assets/`, and commit only the
manifest, Blender cleanup scripts, and the small processed sprites and glTF
files the first art spike needs. Revisit this when the art spike settles the
asset pipeline that [skills-review.md](skills-review.md) lists as unsettled.

## Provenance manifest

One YAML file per asset next to its processed output, for example
`apps/world/assets/crew/goku/asset.yaml`:

```yaml
id: crew/goku
source_url: https://www.deviantart.com/nekopixil/art/FBX-Goku-DB-Sparking-ZERO-3D-Model-DL-1108604555
creator: NekoPixil (port); Bandai Namco / Spike Chunsoft (original game asset)
upstream: "Dragon Ball: Sparking! ZERO"
license_as_stated: fan port, no license stated
distribution: private-only
retrieved: 2026-09-07
blender_version: 4.2.3
modifications:
  - baked materials to albedo + ORM 2k
  - decimated 48k to 9k triangles
  - retargeted to Mixamo rig; rendered 8-direction sprite sheets
outputs:
  - goku_idle.png
  - goku_walk.png
```

`distribution` is `private-only` or `public`. A build check that refuses to
package `private-only` assets into a public export is part of the first world
slice, not a follow-up.
