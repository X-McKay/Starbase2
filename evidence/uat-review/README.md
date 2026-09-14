# Native UAT correction evidence

Synthetic native Godot 4.7.2 views on an Apple M5, Compatibility renderer.
All work and field-command clients were fixture fenced; these captures dispatched
no commands or inference. Screenshots demonstrate presentation, not sandbox or
provider execution. The repair error is a synthetic socket-path failure.

- [Wide structured history](history-wide.png): outcome, target/build, timestamp,
  both findings and qualification. No JSON traversal is needed.
- [Compact repair failure](repair-compact.png): explicit execution failure with
  retained cause and next step; invalid scores are not presented as valid grading.
- [Actual compact reflow](compact-reflow.png): window resized to 800×640 without
  resetting the virtual canvas. Backing-pixel dimensions do not certify initial
  Retina point sizing. This earlier capture precedes final wording refinements.

Reproduce the final Work/repair views using `capture_uat_review.gd` with an explicit
`--capture-dir` under `.local`. It exercises 1280×800 and 800×640 with larger text;
compact results use page scrolling. `capture_uat_native_dimensions.gd` exercises
actual resize and focused-field keys without altering the content-scale size.
Use an external bounded process timeout for automation.

The [assessment](../../docs/uat-report-review.md) records findings, corrections,
validation and open work. Full local diagnostic logs and unsuccessful capture
attempts remain in `.local/uat-review/`; they are not release qualification.
