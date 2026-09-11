---
name: starbase2-world-qa
description: Verify Starbase2 Godot scene, asset, animation, interaction, or local export changes with physical journeys and native visual evidence. Use for world QA and review builds; documentation-only edits need documentation checks, not game qualification.
---

# Verify the playable result and the exact review artifact

Read the requested outcome, affected diff and existing evidence. Use
[starbase2-world](../starbase2-world/SKILL.md) for state/interaction semantics,
and the relevant [production lessons](../../../docs/world-production-lessons.md).
Select checks for the changed surface; don't restart every historical experiment.

For asset organization changes, use the
[content taxonomy](../../../docs/content-organization.md). Verify matching
category/asset IDs across production and runtime, distinguish structures from
rooms and character assets from crew identities, and check all migrated resource,
build, test and documentation references, including Godot `$Node` shorthand
and exported resource include filters. Read the current production index rather
than applying obsolete paths from historical logs. Taxonomy-only documentation changes need documentation checks; actual
asset moves need import/rebuild and affected game checks. Keep linked historical
evidence and paid originals until their retention conditions are satisfied.

## Establish the observable acceptance case

Record what the user will do and what should be visible: e.g. walk into the
structure, inspect a console, walk out, run/stop/turn, then repeat under reduced
motion. Identify decorative effects versus authoritative status. A new costume,
room visit or local gesture cannot assert operational success or dispatch work.

Use the optional [review record](assets/review.md) when a slice needs a shared
handoff. Keep unknown, failed, skipped and passed checks distinct. Record owner
visual acceptance separately from technical qualification.

## Check in layers

1. Inspect asset/import contracts: identity, axes, dimensions, textures, clips,
   runtime references and relevant malformed/missing-input cases.
2. Run focused behavior checks. Structure changes need real physical traversal,
   furniture/edge collisions, enter/exit and direct-visit routes. Character
   changes need displacement/cadence, collision-stop, turning, transitions and
   reduced motion. Include UI/status/audio checks as affected.
   For home/work travel, verify every authored anchor pair in both directions and
   the final segment after grid routing. Require stopped arrival, not passing
   within a distance threshold. Keep seat contact, collision bounds and grid
   rounding consistent; do not weaken clearance to turn a failure green.
   For social animation, clip selection alone is insufficient: inspect native
   standing, transition, seated and return poses with joint/contact measurements.
   Include imported child transforms, scale and skeleton-space tracks; a passing
   Blender-local contact audit cannot certify native deformation. Preserve failed
   captures even when a headless clip test passed.
3. Run `mise exec -- just check-world` for an integrated world change. Inspect
   `scripts/check_world.py` and `scripts/check_world_commands.py` for current
   coverage; a new scene or clip may need a meaningful regression check. The
   native command fixture must remain isolated from production identities.
4. Inspect native Godot at relevant view sizes and renderer settings. Capture
   exterior and interior, important failure/stale states, and animation motion
   plus a close-up when face/helmet quality is at issue. Check framing and actual
   model appearance; a screenshot file merely existing is not visual review.

Godot and Blender can exit zero while logging errors. Require intended outputs
and completion markers, inspect warnings, and reject script/import errors. An
async physics/render check must sample after the relevant update. Preserve an
initial failure and diagnose it; change the cause or test precondition before
repeating. Don't accumulate green reruns or silently loosen a visual threshold.
Record unverified behaviors and avoid claiming FPS improvements without a
comparable measurement on named hardware and settings.

## Qualify a standalone build when the task calls for one

Freeze world sources before `mise exec -- just check-world-export --output
.local/<fresh-review-directory>` (enter this as one shell command). The current
runner qualifies macOS; inspect platform/tool availability before using it.
It runs the exported executable outside the checkout, checks offline fixture
fencing, assets and journeys, captures native views, and binds source/artifact
hashes in a manifest. Extend relevant package coverage for new dependencies.

Do not edit world source while qualification is running. A subsequent source
change needs a new appropriately qualified artifact. Use a fresh output folder
and retain failed-attempt logs. Native captures must complete under a bounded
wall-clock timeout; a fixed frame cutoff can end while macOS awaits a drawable.
Investigate missing captures instead of copying in an editor screenshot. The
macOS harness uses fresh Launch Services GUI instances after a reproduced direct
launch stall; retain native stdout/stderr and restrict timeout cleanup to the
exact isolated executable. A successful launcher exit alone does not prove the
app rendered without errors.

An occluded native window may stop emitting `frame_post_draw` while physics
continues. For explicit automated viewport captures, the qualified helpers use
`RenderingServer.force_draw(false)` before reading the real viewport. Keep this
inside capture mode; it is not a gameplay rendering policy. Preserve a stalled
attempt, distinguish launch failure from missing draw completion, and verify
the correction in the actual exported app without repeated foreground forcing.

Inspect the actual exported captures and qualification result. Describe an
unsigned local review package as such; this does not authorize a commit, push,
deployment or publish. If opening a review was requested/implied, verify its
window and use an offline fixture. Replace only a prior review process known to
belong to this task, preserving other user applications and source files.

## Close the feedback loop

Record changed behavior, checks actually run, relevant metrics, native evidence,
exact artifact, limitations, reproduction and rollback/rebuild instructions.
A passing rigid-head audit covers its measured region; a headless scene pass
is not a visual or accessibility sign-off. Keep the user's art judgment pending
until given.

For a new failure mode, add symptom → evidence → correction → scope → regression
check to the slice record. Promote a rule into the shared lessons/skills only
when it changes a future decision. Revisit rules that cause misrouting or excess
work; do not store raw transcripts as automatically accepted runtime memory.
