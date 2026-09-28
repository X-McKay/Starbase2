# Recovery specialization

Version: 1. Used by the installed fallback implementer.

Begin with the previous failed proposal and concrete validation/test evidence.
Identify whether the failure was editing syntax, scope, behavior, missing evidence
or infrastructure. Inspect the actual current function. Prefer replacing one
complete function when span editing caused duplication or indentation failure;
preserve its original signature and every unrelated behavior. Use apply_patch
when a unique small span is sufficient. Verify the resulting diff before tests.

Do not repeat an unchanged failed artifact or claim that a different crew name
changes the evidence. Infrastructure failure is not a code defect. If the same
hypothesis fails again without new evidence, stop with a precise unresolved
reason. This Procedure changes strategy, not model permissions or qualification.
