# Living colony local review

Branch `codex/living-colony-frontend`, base `9dc417b`. Status: complete-milestone
export qualified for local review; corrected world and repository checks passed.
Nothing was published or deployed. The earlier
[remaining-structures review](../remaining-structures/README.md) remains historical
evidence for its own exact artifact.

The [production design](../../../assets-production/batches/living-colony/DESIGN.md)
records the imagegen storyboard, retained Meshy inputs, interior architecture and
interaction markers. This milestone adds no Meshy spend: 507 actual credits,
0 pending and 743 remaining under the prior task allowance.

## Implemented presentation

Command retains bridge ribs and observation glazing during cutaway. Training
shows paired vaults and practice mats. Habitat gains wood/linen material zones,
privacy wings and dining detail. Botanical gains retained conservatory arches,
overhead irrigation and planted detail. All use the existing generated hulls and
equipment, with separate exact collision and interaction anchors. A 10 × 7.1 m
commons at the reserved (-7, 23) plot creates a shared colony destination.

Quieter HUD surfaces, authored cameras, room guides and equipment-based inspection
bring attention to the place. Optional audio and breeze remain decorative. Sound defaults muted; reduced
motion suppresses breeze, while explicitly enabled steady audio can continue. Existing operational IDs and authority remain preserved;
room furnishings never imply backend outcomes.

## Evidence so far

The [Command representative slice](command/) passed physical approach/interior/
console/exit, cutaway, direct visit, reduced motion and no-dispatch checks. Its
actual image was reviewed before the other interiors were expanded. Source
marker checks also found all Console/Crew/WalkTarget points clear of furniture
rectangles expanded by the player radius.

The [native-v2 captures](native-v2/) review the complete composition after lighting
was reduced from the overly orange first pass. Do not use an earlier image to
certify the latest source. All four interiors have now been visually reviewed. Corrected world/repository
checks passed; fresh standalone export qualification passed in `20260907-final-03`. Source files must remain frozen
through export; the final manifest must bind the exact reviewed source/artifact.

Owner art judgment remains open. Inspect retained arches for camera occlusion,
Habitat furniture scale and comfort, Botanical material readability, commons
placement and clear routes, and compact HUD readability. A clean still image
does not establish collision, keyboard access or stale/offline correctness.

The native-v2 Command, Training, Habitat and Botanical interiors, commons and
compact Command workspace were independently viewed. Command's retained bridge
structure and cooler light improve focus; Habitat's alcoves and wood floor give
it a distinct domestic identity. No obvious hull clipping appeared in these
views. Remaining art judgments: Training's initially floating sections were connected back to the rear structure
with high beams, and Botanical's blocky edge leaves were replaced with pointed
blades. Both corrections were seen in the first exported interior views.
Habitat's table remains partly hidden by chairs from its camera; commons roof slats
obscure furniture at the overview scale. Compact workspace content is readable,
although Crew and Journal top buttons truncated in this intermediate capture;
the final package controls were corrected and inspected as readable. These observations do not replace
physical, accessibility or exact-artifact qualification.

## Corrected verification and retained attempts

The complete offline `world-living-build` recipe completed without Blender
errors, and 96 Engineering/character preservation hashes matched. The repository
suite passed in [check.log](final/check.log). The full world suite passed after
updating an outdated roster-scroll assertion, retained in
[check-world-scroll-corrected.log](final/check-world-scroll-corrected.log).
The original [world failure](final/check-world.log) remains inspectable.

The first standalone attempt passed all physical journeys, motion and native
log checks, but qualification correctly rejected changed source hashes during
an intentional test edit. Its [qualification log](final/export-qualification.log)
is retained as a failed artifact binding, not a qualified build. Compact HUD
labels also required a correction before the next attempt.

The final local unsigned review archive is
`.local/reviews/living-colony/20260907-final-03/Starbase2-macOS.zip`.
The [qualified manifest](final/package-03/manifest.json) and complete durable
[package evidence](final/package-03/) bind and document the reviewed artifact.
Archive SHA-256:
`9d23b98160b74822fcf055d2e2b055e00f082d30b9c14f0e82d523c9bd8018e2`.
Qualification passed with exit zero. Owner art approval remains separate.

The commons camera, foliage breeze and slat cutaway are implemented; the arrival
view keeps the player visible while roof slats fade. Optional room ambience is
muted by default. Still images do not certify motion or accessibility, which
remain part of the fresh standalone qualification. Current concrete art limits
are Habitat chair/table occlusion and deliberately opaque exterior glazing.

The second export attempt was intentionally stopped after independent review
found back-face culling on decorative leaves; retain
[export-02-superseded.txt](final/export-02-superseded.txt). A dedicated two-sided
leaf shader corrected the issue. The targeted check inspected all three actual
foliage surfaces ([foliage-material.log](final/foliage-material.log)), and the
[living journey](final/living-foliage-final.log) passed afterward. The foliage
check is now registered in the suite. The full world pass preceded this narrow
shader correction; it is not claimed as a full-suite rerun of that correction.

The third export qualified against frozen sources. Current production provenance covers 221 selected input files and 96
preserved Engineering/character files. This production selection is not the
complete world source binding: the export manifest owns that exact artifact and
source record. Reduced motion suppresses decorative breeze, not steady optional
audio; sound remains muted until explicitly enabled.

## Final inspected result and measurements

The actual final package's four exterior/interior pairs, both room guides,
[wide Command board](final/package-03/command-workspace.png),
[compact Command board](final/package-03/command-workspace-compact.png),
[motion strip](final/package-03/review-motion.png) and
[commons](final/package-03/living-commons.png) were inspected. Foliage coverage
is restored with the two-sided shader, and compact controls are fully readable.
Remaining art judgments are Habitat's table partly occluded by chairs and
deliberately opaque textured glazing. These do not imply owner art acceptance.

Measured on Apple M5, OpenGL 4.1 Compatibility, Godot 4.7.2:

| View | Resolution | Median frame | p95 frame | First frame |
|---|---|---|---|---|
| Colony | 1280 × 800 | 16.686 ms | 19.402 ms | 7001 ms |
| Interior | 960 × 720 | 16.929 ms | 30.987 ms | 7075 ms |

These describe this local run; there is no comparable baseline establishing a
performance improvement. Full world checks preceded the narrow foliage shader
fix; focused actual-material/living-journey tests and the fresh final standalone
run cover that correction. No publishing, deployment or owner art approval is
claimed.

The qualified archive was extracted into its local `playable/` directory. Its
executable and pack hashes match the manifest. The app was opened with the
offline stale fixture and Command starting room; native UI inspection confirmed
the rendered window. The final 525-file world source tree still matches the
qualified manifest.

Rebuild with `mise exec -- just world-living-build`, then qualify into a fresh
review directory. Preserve the selected paid originals and ledgers required by
the production recipe. To return to the previous review, use the unchanged
remaining-structures artifact; this milestone has no backend migration or
deployment to roll back. Local source work remains on
`codex/living-colony-frontend`, without a new commit or push.
