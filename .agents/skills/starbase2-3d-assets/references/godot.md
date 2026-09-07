# Connect an asset to the existing world

Read the affected [building catalog](../../../../docs/building-catalog.md),
[character contract](../../../../docs/character-production.md), and actual scripts.
Use data/resources for cosmetic selection; don't bind a costume to operational
permissions or fabricate new crew identities to match animations.

## Structure journey

Trace approach → threshold → interior route → inspection console → exit. Include
keyboard and directory/direct-visit paths. Keep footprint, opening, room bounds,
prop colliders and navigation derived from consistent layout data. Test the
actor's real radius/clearance, not just an empty ray through the door.

Continuous rooms remain in world coordinates. An automatic cutaway should not
teleport the player or hide the surrounding colony. Check both closed exterior
and open interior: props, crew or an authored rear wall can protrude through a
narrower generated hull. Reveal interior-only surfaces at the appropriate
cutaway state; retain needed shadows without visible duplicate roofs. Leave
routes clear of decorative risers, lockers and consoles, with collisions where
needed. Preserve existing user edits when reconnecting generated scenes.

See the existing station/room/definition scripts and
[Engineering connection](../../../../assets-production/scripts/connect_engineering.py).
Its coordinates and names belong to that slice. If a broad colony rebuild would
overwrite a selected scene, update the rebuild recipe to reapply that selection.

## Character journey

Set the model, scale, floor offset, label height and stride in the character
resource. Advance gait from actual displacement, including collisions and
teleport resets. At running speed, use a run clip and suitable stride if
available; retain an explicit fallback for models without that clip. Blend
changes in pose/heading and test the planted feet, not only clip selection.

An inspection gesture follows local UI interaction; activity labels follow
authoritative records. Opening a panel or moving through a room must not dispatch
work. Reduced motion uses a stable pose and stops decorative effects; sound
defaults off. Keep portraits and structured inspection usable independently of
the 3D presentation.

Verify materials using this project's Compatibility renderer. A custom cutaway
shader must preserve imported PBR textures and flags. Test muted audio, light and
rotor behavior as observable states. Use
[world QA](../../starbase2-world-qa/SKILL.md) to close the slice with evidence.
