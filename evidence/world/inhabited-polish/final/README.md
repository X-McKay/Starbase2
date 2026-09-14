# Final inhabited polish qualification

Focused `test_remaining_structures.gd`, `test_inhabited_journey.gd` and `test_living_colony.gd` passed with clean exit 0. Then `mise exec -- just check-world` and `mise exec -- just check` passed sequentially; complete logs are retained here. The repository check reports existing integer-format generator fallback warnings, normal generated-model lint correction, and matching contracts.

`native/` contains the actual live all-four room journey captured through pinned Godot 4.7.2/macOS Launch Services, bounded to 240 seconds. Exit 0, stderr empty, no capture failures; 16 frames plus 12 motion frames. All 553 world files matched the native launch hash snapshot after both suites. Camera and world processing remained enabled.

Reviewed the four interior frames. Habitat's generated green sofa seat points inward toward the coffee table. The east sidewall partially occludes its rear/profile, but no reversed orientation or furniture intersection is evident. Each room's fan sits at its rear-right wall: above the Habitat pod and Botanical tank, beside the Command/Training rear framing. No detached fan or entrance obstruction is evident. Native stills cannot alone prove subtle hair movement or fan motion; the focused character/vent tests and character agent's close-up native evidence complement these frames. Standalone packaged qualification remains owned by the parent task.

Earlier furniture-test precondition failures and their diagnosis remain preserved in the parent evidence directory. The test now selects a clear cardinal approach, verifies the capsule corridor and room containment, fails if no valid approach exists, and preserves the >0.26 m physical stop clearance. Runtime collision behavior did not require correction.

Standalone `20260908-final-01` subsequently qualified with clean exit 0 and all
553 world files matching the frozen source. `package-01/` retains the manifest,
logs and actual exported PNGs. The archive is
`.local/reviews/inhabited-polish/20260908-final-01/Starbase2-macOS.zip`; the
extracted playable executable and PCK match their manifest hashes. Root inspected
the exported Habitat and water frames: intended sofa orientation/materials,
fan mounting and spring appearance are present. Sidewall occlusion remains.
This is local unsigned macOS qualification, not a deployment. Owner art
acceptance and human audio audition remain open.
