# Shadow stability and crew grounding

Status: proposed

Implementation is complete locally; combined qualification and owner visual
acceptance are tracked separately.

The native orthographic camera inherited a 4,000-unit far plane. A moving-camera
comparison showed coarse, displaced or missing small-caster shadows. The selected
correction uses one directional shadow map and a finite camera depth that grows
continuously with the rendered view size. Sun color, energy and direction stay
the same; this is a rendering correction, not operational state.

[`shadow_quality.gd`](../apps/world/shadow_quality.gd) owns the small policy.
The minimum depth is 160 units; wider views add camera-offset length, 0.9 times
the orthographic size and an 80-unit margin. Updating from the actual interpolated
camera size avoids discrete depth changes during smooth zoom. The widest Map
view retains coastline coverage. Godot documents the distinction between a
[single orthogonal shadow map and perspective cascades](https://docs.godotengine.org/en/stable/classes/class_directionallight3d.html),
and the [detail/coverage tradeoff](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html).
The local native measurements, rather than documentation alone, selected this
configuration for the project's Compatibility renderer.

Normal bias remains 2.0. A controlled reduction to 0.5 brought thin-caster shadows
closer but introduced severe repeating shadow-acne stripes on soil and interior
flooring, so it was rejected. Some thin-blade shadow separation remains a known
tradeoff; lowered bias is not presented as a completed improvement.

Crew contact cues now use a faint transparent elliptical plane instead of the
old opaque teal cylinder. [`crew_contact_shadow.gdshader`](../apps/world/crew_contact_shadow.gdshader)
has no animation; the existing support-surface sample still places it just above
the floor. It adds neither collision nor another cast shadow. Real directional
shadows provide the main shape and direction.

[Native evidence and retained experiments](../evidence/world/shadow-stability-20260928/README.md)
include identical camera pan/zoom sequences, maximum-Map depth comparisons and
same-camera contact-cue comparisons on sand/paving and Habitat flooring. The
measured fixed-ground shadow drift is reduced. Sharper edges retain some
subpixel variation; this does not claim perfect temporal stability, a performance
gain, universal renderer support or completed export qualification.

Focused checks cover continuous depth, visible ground/coast bounds, the actual
world configuration, camera controls and movement, contact grounding, reduced
motion and no dispatch. Parent-owned combined qualification includes these with
the other visual changes. Rollback restores the prior camera/sun configuration
and contact mesh; no data migration or external effect is involved.

Concrete visual follow-ups remain owned by world presentation:

- At maximum Map zoom-out, the rectangular ocean edge is visible against the
  starfield in both old and corrected depth views. Acceptance: conceal or extend
  the finite water backdrop across the supported Map range without changing
  physical coastline bounds.
- Nearby crew labels can obscure torsos in Commons at the closer gameplay scale.
  Acceptance: keep names/status readable without covering the selected crew's
  action, with the structured caption and keyboard inspection preserved.
