---
name: starbase2-3d-assets
description: Create, adapt, or integrate Starbase2 3D structures, props, and rigged characters using Meshy, Blender, and Godot. Use for asset-production work; ordinary HUD or state-projection changes use starbase2-world.
---

# Produce a playable asset, with a reproducible source

Read the affected scene and [world production lessons](../../../docs/world-production-lessons.md).
Use [starbase2-world](../starbase2-world/SKILL.md) for journey and truthful-state
requirements. Finish one requested review slice before expanding its art set.
Existing user authorization persists; a skill does not require re-approval of an
already authorized scope or credit cap.

## Choose the work from the supplied asset

Inspect the actual source before proposing generation. A shared model may have
textures but no rig or animation. Confirm identity, file contents, topology,
scale, axes, PBR channels, skeleton and clips. Distinguish an exact downloaded
model from a newly generated interpretation of its reference.

- For Meshy retrieval or generation, read [Meshy workflow](references/meshy.md)
  and use the installed [Meshy skill](../meshy-3d-generation/SKILL.md).
- For mesh, material, rig or animation preparation, read
  [Blender preparation](references/blender.md).
- For a playable structure or character, read
  [Godot integration](references/godot.md).

Use a concept image when it resolves art direction or improves generation input;
a clean supplied asset does not need to be regenerated. Static structures do not
need rigging. Prefer editable authored architecture for predictable traversable
space, with generated assets as detailed hulls, props or characters.

## Keep the asset chain inspectable

Follow the [content taxonomy](../../../docs/content-organization.md):
`assets-production/<category>/<asset-id>/` and
`apps/world/assets/<category>/<asset-id>/` share categories and IDs. Use
`structures`, `characters`, `props`, `kits`, or `environment`; use `concepts/`,
`originals/`, `blender/`, and `scripts/` within production assets as needed.
Keep animation-selection/gameplay behavior in runtime code, not production.
Use the [production index](../../../assets-production/README.md) for current
recipes. Shared preparation lives in `assets-production/scripts/`; multi-asset
plans and provenance live in `assets-production/batches/`, not runtime categories.
Keep required `meshy_output` inputs and ledgers until a verified restoration or
migration exists. Hydrate `.blend` sources with Git LFS before Blender work;
Playing/exporting uses committed runtime assets; the full world suite also
verifies pilot source hashes and needs hydrated sources.
Record source/task IDs, actual credit charges, tool versions, output hashes,
geometry/texture budgets and the connection to the runtime resource. Credentials
and expiring signed URLs do not belong in committed provenance.

Use the pinned tools and current `justfile` recipes. Existing Engineering and
Vanguard scripts are working examples, not universal importers: inspect their
asset IDs, bone names, geometry assumptions and output paths before reuse. A
source rebuild must preserve the selected runtime connection and perform no paid
calls unless explicitly requested. Preserve the user's live Blender scene;
work in a separate file/process for destructive preparation.

## Accept the result in the game

A concept, Blender render or successful GLB import is an intermediate result.
Use [starbase2-world-qa](../starbase2-world-qa/SKILL.md) for applicable native
visual, physical, accessibility and package checks. State what remains an art
judgment rather than calling a technical pass owner approval.

After a meaningful failure, capture the symptom, evidence, fix, scope and
regression check in the slice evidence. Promote only the reusable lesson into
the linked lessons record or this skill; do not turn every model-specific
coordinate or workaround into a universal rule.
