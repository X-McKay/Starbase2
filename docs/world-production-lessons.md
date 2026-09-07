# World asset production lessons

Status: accepted

Owner: Al McKay. Recorded: 2026-09-07.

Scope: reusable development guidance from the Engineering and CyberCat Vanguard
slices. This is a curated evidence record, not runtime agent memory or permission
to generate, publish or deploy. The art direction still awaits the owner's
judgment; technical qualification is recorded separately.

## Workflows now worth reusing

Use [3D asset production](../.agents/skills/starbase2-3d-assets/SKILL.md) for
retrieval/generation, Blender preparation and integration, and
[world QA](../.agents/skills/starbase2-world-qa/SKILL.md) for playable verification
and review artifacts. The original [world skill](../.agents/skills/starbase2-world/SKILL.md)
continues to own truthful state and interaction semantics. The installed Meshy
skill owns endpoint/client details; these new skills add project experience.

| Observed issue and evidence | Reusable practice | Scope / what not to assume |
|---|---|---|
| Vanguard's shared GLB had no skin or clips; [source provenance](../assets-production/characters/cybercat-vanguard/provenance.json) records the exact asset | Inspect actual file contents before promising animation or regenerating a model | A model viewer pose or a newer model version does not prove better animation |
| Website task metadata was readable but rigging by task ID returned HTTP 400; the returned GLB URL succeeded ([record](../evidence/cybercat-vanguard/README.md)) | Keep a supported source-URL path after a definite task-ID rejection; retain the original failure | This is not a reason to blindly retry every failure or bypass an uncertain submission |
| An earlier 60-credit batch and a 140-credit Engineering batch initially had separate accounting; Vanguard added 8 ([provenance](../assets-production/batches/engineering-polish/provenance.json)) | Count prior batches and pending reservations under the user's total cap; reuse existing authorization | Provider account balance is not the authorized budget; historical prices are not future quotes |
| Engineering bounds included a rig control Icosphere ([inspection](../evidence/engineering-polish/rig-inspection.log)) | Select intended skinned meshes and update evaluated transforms before measuring/exporting | Do not rescale a valid character to compensate for unrelated control geometry |
| Imported bone tails exceeded joint spacing; console baking also lost correct hierarchy ([record](../evidence/engineering-polish/README.md)) | Reproduce the tail defect; preserve bind orientation and bake parent-relative transforms/action slots | No universal tail multiplier or bone naming convention is established |
| Face/helmet vertices had shoulder influence ([Vanguard weights](../evidence/cybercat-vanguard/source-weights.json)) | Locate the actual collar, stabilize the rigid region and preserve a flexible neck transition | Do not copy a previous model's height threshold or certify the entire character from one region |
| The first Vanguard audit included nearly rigid neck vertices; [final audit](../evidence/cybercat-vanguard/helmet-audit.json) measures fully rigid vertices | Define the measured region and units; match export influence limits before measurement | A changed selection needs explanation; do not relax thresholds just to pass |
| Generated hull shape exposed authored rear-wall/furniture geometry in exterior views ([iterations](../evidence/engineering-polish/README.md)) | Review both exterior and cutaway; align collision, doorway, visibility and interior dressing | A plausible Blender render does not prove physical access or correct native occlusion |
| Character speed shared a short walking stride; [cadence check](../apps/world/test_run_cadence.gd) now measures physical travel and contacts | Use displacement-driven walk/run cadence, collision-stop and reduced-motion tests | 1.6 m / 2.8 m are current player settings, not universal rig values |
| An interior reveal assertion sampled before the physics update ([record](../evidence/engineering-polish/README.md)) | Wait for the relevant update and test observable arrival/visibility | Do not hide a timing defect behind arbitrary long sleeps or repeated retries |
| The first standalone capture ended without an interior image; [qualification log](../evidence/engineering-polish/package-qualified.log) passed after retaining a bounded wall-clock wait | Let capture completion end the scene, preserve failed attempts and require real exported images | The precise OS drawable timing was not independently isolated; do not label every missing capture the same bug |
| Local source continued evolving between reviews; the [export runner](../scripts/check_world_export.py) binds source/artifact hashes | Freeze the source during qualification and publish a new local artifact for later changes | A previously qualified package does not certify subsequent source edits |

## Evidence and reusable implementations

- [Engineering review](../assets-production/batches/engineering-polish/REVIEW.md): concept to hull/reactor,
  authored interior, tested continuous journeys, native captures and limitations.
- [Vanguard review](../assets-production/characters/cybercat-vanguard/README.md): exact supplied asset,
  rigging, 2K game textures, face/helmet stabilization and runtime selection.
- [Preparation](../assets-production/scripts/prepare_character.py),
  [rigid-region audit](../assets-production/scripts/audit_character.py), and
  [building connection](../assets-production/scripts/connect_engineering.py): working
  implementations with asset-specific assumptions to inspect before reuse.
- [World checks](../scripts/check_world.py) and
  [standalone qualification](../scripts/check_world_export.py): executable checks,
  not a substitute for inspecting their actual coverage and native output.

Raw generation originals remain in ignored `meshy_output`; qualified local
packages/manifests remain under `.local`. Keep selected sanitized provenance and
review evidence in the repository. Do not treat machine-local artifacts as
available on every checkout or automatically export credentials/signed URLs.

## How this record improves

At the next structure/character slice, the implementing agent records a concrete
failure or success, evidence, cause or uncertainty, correction, scope and an
observable regression check. Al owns visual acceptance and review of material
workflow changes. Promote a short instruction only when it changes a future
decision; keep case-specific detail with the slice. Remove or narrow guidance
that causes unnecessary generation, approvals, tests or incorrect routing.

Completion condition for the next skill review: apply these skills to one new
structure or character, retain the resulting native/package evidence as relevant,
and record which instructions helped, misrouted or missed a failure. The current
skills have static validation and scenario self-review, not an independent
behavioral effectiveness study or verified discovery in every host.

## Content migration follow-up — 2026-09-07

The [migration record](../evidence/world/content-reorganization/README.md) retains
the source/runtime mapping, duplicate-removal hashes and actual package review.
A directory rename also needs Godot `$Node` shorthand and export include filters
checked. Editable Blender libraries may contain valid datablocks without a scene;
a source audit must distinguish those from empty/broken assets. A second direct
macOS GUI launch stalled before engine output; Launch Services rendered the same
archive and the fresh qualification passed. Use the current export harness,
including its native error checks and narrowly scoped timeout cleanup. The exact
OS cause was not isolated, so do not generalize this to all launch failures.

## Remaining structures — 2026-09-07

The first authored template pass remained too plain for the owner's requested
standard. Increasing object count alone did not solve the shared box silhouette.
The correction used built-in imagegen for ambitious matching exterior/cutaway
plates, Meshy for four distinct whole hulls and nine useful furniture assets,
and Blender to fit them around exact larger rooms. Command's initial table and
analysis consoles also appeared too small; their preparation fit limits and
room composition were enlarged before continuing. Review the actual native
camera scale early, not only an isolated provider thumbnail or fit target.
See the [selected production design](../assets-production/batches/remaining-structures/DESIGN.md)
and [final native captures](../evidence/world/remaining-structures/final/native/).

Generated doors and shell interiors are visual suggestions. The playable
opening, moving leaves, floor and collision stayed authored separately; hull
preparation cut a real clearance, and named groups controlled exterior fade and
rear-wall reveal. Retiring the superseded authored roof and side-wall preview
prevented it from competing with the selected hull. Native exterior and cutaway
views remain required because an imported hull alone does not establish usable
clearance or concealed interior geometry.

Larger rooms also required moved pads and an eastern/southern plateau extension.
The first protected-spring collision check failed before correction. Reconcile
paving, structure footprints and protected landscape obstacles together, and
retain the initial failure alongside the corrected check. Enlarging a terrain
outline is not by itself proof that relocated rooms and paved approaches fit.

Independent review of the eight final native exterior/interior images found
clear room identities and no obvious major hull/furniture clipping in those
views. The Botanical exterior uses opaque textured glazing with foliage imagery;
it does not show the actual interior through glass. All rooms share the exact
paneled rear-wall construction and keep generous floor space, most noticeable
in Training and Habitat. Those art judgments remain for owner review, separate
from physical traversal and export qualification.

Concrete optional art follow-ups: evaluate a warmer, more furnished Habitat
commons and Training practice-floor detail at the actual camera scale; soften
the shared back-wall treatment per room; and consider true conservatory glazing
only with verified Compatibility/cutaway behavior. The first captured Botanical water pipe ended unsupported in the room; the
builder now connects it horizontally toward the bench and adds a vertical
downleg to 1.4 m. A later full-world route check also found a scattered outcrop
near the Botanical approach; its authored position moved from (12, 35) to
(10, 42), and the corrected full world suite passed. These are review follow-ups, not a claim that more generation
is required or that technical checks establish owner art approval.

The first standalone remaining-structures export exercised native journeys but
was correctly rejected when motion-contact-sheet blitting reported an image
format error. Explicit RGB8 conversion corrected the capture code; qualify a
fresh build after that source change rather than inheriting the failed package's
status. Full world and repository checks subsequently passed. Standalone export
qualification subsequently passed in `20260907-final-02`. The pipe correction is visible in the first
export's Botanical interior capture; visual confirmation does not override its
unrelated capture-format qualification failure.

Final qualification: the unsigned macOS `20260907-final-02` review passed, with
exact source/artifact hashes in its manifest and an inspected nonblank 12-frame
motion contact sheet. Full world checks preceded the capture-only RGB8 fix;
the fresh standalone run covers that final capture change. This establishes
local technical qualification, not owner art approval or deployment readiness.
