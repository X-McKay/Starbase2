# Surface detail and visual coherence

Status: proposed

The scoped local implementation, native reviews, integrated world suite and
[standalone export qualification](../evidence/world/production-polish-20260928/README.md)
passed. Owner art acceptance remains separate.

This pass follows the closer-camera and Precise crew-motion review. Its purpose is
to make ordinary movement and close inspection convincing, before Kubernetes or
Flux deployment. It does not simulate operational activity.

## Temporary regolith footprints

The Commander and all five crew can leave boot impressions on the exposed soil.
The existing displacement-driven gait emits contacts; sparse probes of the final
deformed sole locate the grounded foot. Standing, collision stops and teleports
produce no new contact events. A footprint is admitted only when its complete
extent lies on playable soil at terrain height. Paving, raised floors, Commons
wood decking and airborne feet are rejected.

The impression plane follows the rendered soil at Y=-0.035, within 5 mm of its
surface, rather than the separate navigation datum. A shared 128-instance pool bounds geometry and retained bookkeeping. Impressions
show a broad toe, separate heel and tread, soften after 8.4 seconds, and disappear
by 24 seconds. Repeated crossings reuse the oldest slot. They cast no shadows,
write no depth, change no collision, and have no saved or operational meaning.
Reduced motion hides the effect and suppresses new prints; sound remains governed
by its separate preference. No generated image or paid asset is required: the
editable material and contact sampler are repository source.

The [surface review](../evidence/world/surface-details-20260928/README.md) records
native close/gameplay/faded/expired views, contact checks and limitations.

## Broader app review

Inspection of the preceding qualified native export also found:

- Interior roof ribs can still obscure consoles and crew after a roof opens.
  The [roof-only cutaway correction](../evidence/world/interior-sightlines-20260928/REVIEW.md)
  clears those overhead spans while retaining rear structure and physical walls.
  Native same-camera comparisons and all-four-room physical-contact checks passed.
- Exterior grass uses flat triangular blades; Commons and Botanical leaves also
  read as paper from close angles. [Closed curved blades and branching silhouettes](dimensional-vegetation.md)
  now replace those forms, with bounded geometry and shared materials.
- Opaque teal crew grounding discs read as solid character bases. A [soft neutral
  contact treatment](shadow-quality.md) replaces those discs.
- [Bounded camera depth and one orthographic shadow map](shadow-quality.md)
  reduced measured shadow drift in the native pan/zoom comparison while retaining
  full Map coverage. Residual subpixel shimmer and thin-leaf shadow separation
  remain limitations; lower bias caused striping and was rejected.

The following are review findings, not claimed fixes or accepted art direction:

| Opportunity | Concrete next review slice | Completion condition |
| --- | --- | --- |
| Label overlap | Nearby actor names and multi-line building summaries | Same-camera crowded doorway/interior views preserve identity without covering faces, hands or entry points; structured details stay reachable |
| Furniture fidelity | Shared chairs, benches and pendant fittings | Beveled silhouettes and coherent material response compared beside detailed consoles; unchanged physical clearances and seated contact |
| Map backdrop edge | Rectangular ocean mesh boundary visible at maximum zoom-out | Full Map pan/zoom preserves an intentional horizon with no rectangular water cutoff against the starfield |
| Water treatment | Bright grid/concentric lines and abrupt shoreline | Native moving and reduced-motion views show calmer surface/depth cues without hiding the physical bank |
| Reading surfaces | Hull lines visible beneath translucent detail panels | Compact large-text dossier/stale-record views retain contrast over the brightest background and keyboard access |

These slices belong to the world/asset workstream in the
[delivery plan](autonomous-rpg-delivery.md). They are visual-quality follow-ups,
not permission to broaden backend authority. Technical checks and local export
qualification remain separate from the Commander's visual sign-off.
