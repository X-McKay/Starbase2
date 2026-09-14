---
name: starbase2-world
description: Design or change Starbase2 Godot scenes, crew presentation, RPG progression UI, or the compact operations view. Use when interaction, visual state, accessibility, or semantic animation changes.
---

# Make the world enjoyable and inspectable

Read [experience intent](../../../docs/experience.md) and inspect the current
scene, state contract, and assets. The theme and layout remain design hypotheses;
do not recreate the predecessor outpost merely because its assets exist.

Start with the operator journey and authoritative state. Map an operational
visual to its owner, triggering event/projection, freshness, evidence link, and
pending/terminal behavior. Clearly decorative ambient life may be locally
simulated; it cannot imply real work, agent reasoning, success, or incidents.

Keep data projection, interaction state, and rendering separate. Travel never
starts, blocks, or completes work. Unknown/stale/partial states cannot reuse a
healthy animation; reconnect coalesces obsolete motion without losing history.
One crew member with concurrent runs needs task markers, not invented identities.

For inhabited crew behavior, reserve authored home/social anchors across actors.
Keep cosmetic dwell and travel separate from assignment state; interruption and
fast completion must coalesce immediately to current intent. Stale/offline holds
must not teleport actors. Resolve visibility using the occupied building, not only
the assigned workstation. Expose bounded route failure without changing job state.

For a substantial visual redesign, derive a target from the existing native view
and use an independent target-versus-current critic with comparable framing.
Retain concrete gaps and regressions. Visual scores guide iteration; they do not
replace truthful state, physical journeys, accessibility or measured performance.

Give the journey a keyboard and structured non-spatial path. Keep evidence,
decisions, and stop controls available when the renderer fails. Apply reduced
motion, text scaling, sound-off behavior, and color-independent status where
affected. Camera state is not domain state.

Prefer small authored scenes and reusable existing components. New agent
capabilities do not require buildings. For progression, preserve the distinction
between cosmetic XP, build-scoped proficiency, and operational permission.
No grinding or animation may gate essential controls.

Run applicable state/contract and headless scene checks, then inspect the actual
UI at relevant sizes and failure states. Keep captures with the handoff. Measure
the affected frame-time/startup/event-load behavior before making performance
claims. Do not treat headless startup as visual or accessibility verification.

Handoff: journey, event mapping, observed visual/accessibility states, captures,
measurements, and any unverified export or platform. An API change additionally
uses the compatibility checks in `starbase2-feature`.


For Meshy/Blender asset production, use
[starbase2-3d-assets](../starbase2-3d-assets/SKILL.md). For substantial scene,
animation or local review-build validation, use
[starbase2-world-qa](../starbase2-world-qa/SKILL.md). Ordinary HUD/state edits
still use this procedure and proportionate checks; do not load asset-generation
instructions just because the scene contains a 3D model.

Use the [content taxonomy](../../../docs/content-organization.md) when naming or
organizing assets and scenes. Use `structures` in category, catalog and gallery names. Coordinate any further
resource, scene-node and caller changes; the current index records actual paths.
Crew roles and room contexts remain distinct from character and structure assets.

## Bundled visual references

For visual work, read [the visual guide](references/visual-guide.md). Its selected
images are bundled below; no local evidence archive is needed to use these
examples. They illustrate intent and review cases, not current-build certification.

- [crew-overview.png](assets/crew-overview.png)

- [crew-compact.png](assets/crew-compact.png)

- [habitat-art-target.png](assets/habitat-art-target.png)

Image identity and source type: [visual manifest](assets/visual-manifest.json).
