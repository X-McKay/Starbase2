# Remaining structures baseline

2026-09-07; baseline source commit `a53f5721aa6c2ebdc95c52a30898c2a679232d36`.
World source and runtime assets were unchanged during baseline qualification.
The new capture/contact harnesses are test additions only.

- GitHub Documentation and Local runtime completed successfully at this commit;
  exact run URLs and status are in [ci.json](ci.json).
- All 20 tracked editable Blender inputs were hydrated (`*`), recorded in
  [lfs-hydration.txt](lfs-hydration.txt).
- `mise exec -- just check-world` passed with exit 0 and no logged errors in
  [check-world-unsandboxed.log](check-world-unsandboxed.log). Its first attempt
  [check-world.log](check-world.log) failed because the sandbox prevented Godot
  from saving its normal editor settings. The corrected run used normal native
  application access; no product source or assertion was changed.
- Native Godot Compatibility captures on Apple M5 completed with the explicit
  `REMAINING_STRUCTURES_CAPTURE_PASSED` marker and clean native stderr. These
  used an offline stale fixture and reduced motion. Actual inspected captures:
  [colony](colony.png), [Command exterior](review-exterior.png),
  [Command interior](review-interior.png).
- Command's current exterior is a plain rectangular shell with a small dish;
  its cutaway reveals a sparse central table and three consoles. These are
  baseline art observations, not owner acceptance.

## Regression coverage and next qualification

The existing `test_seamless_colony.gd` physically walks all five structures from
return/approach through the interior to the console and out, checks continuous
displacement, full cutaway, auto-closing doors, direct visits, reduced motion and
no dispatch. `test_rooms.gd` covers physical furniture/edge collisions and
stale/offline console state for Engineering, Command and Training; its analogous
physical furniture checks did not cover Habitat and Botanical.

The new `test_remaining_structures.gd` fills that gap across all four remaining
structures, contacting every declared furniture block and the faded right wall,
checking direct visit/exit and reduced cutaway, and retaining scenery-only
activity for the two unbound structures. Its first sandboxed run completed all
assertions but logged user-log/certificate access errors
([structure-contact.log](structure-contact.log)); inspect the corrected normal
application-access [run](structure-contact-unsandboxed.log) for clean outcome.

Run the focused contact check with `--fixed-fps 60`. Keep the existing continuous
journeys and generic asset/anchor checks; the new contact test does not replace
them. Camera framing and generated hull/interior intersections require native
visual review. The capture harness accepts `--output=<absolute-directory>` and
optional `--only=review|gym|habitat|greenhouse`, plus the required `--fixture=`.
It captures the colony and each requested exterior/cutaway in one native launch.
Use bounded Launch Services execution and check every written image and log.

After integration, run focused checks, the world suite and repository checks,
then freeze all world sources before standalone macOS export qualification.
The package harness must bind the resulting exact source/artifact hashes and
include coverage of new runtime assets. Editor captures cannot qualify that
standalone artifact. Keyboard access, native framing/occlusion, reduced motion
and stale/offline presentation remain required final review surfaces.
