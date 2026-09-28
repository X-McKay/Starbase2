# ADR 0014: Bounded repair tool sessions

Status: accepted

Date: 2026-09-28. Owner: runtime/evaluation. Operator approved the tool, Procedure,
recovery and evaluation improvements following retained Qwen development failures.

## Decision

Extend the current PydanticAI SDLC package with isolated local inspect/edit/test
sessions. Keep Core as independent grader and external-effect authority. Tools
mutate only a digest-bound in-memory captured function; execution uses the existing
credential-free microVM. Public feedback can guide edits, but independent grading
remains outside the agent. Package Procedures and configuration in immutable builds.

Retain the legacy single-response profile as the default until the new profiles
have evaluation evidence. Add separate tool/non-thinking and tool/thinking arms.
A fallback Procedure changes editing strategy without creating another service
or claiming specialist qualification. Existing workflow retries do not repeat
model activities automatically; bounded in-session attempts retain evidence.

## Rationale and alternatives

Retained failures involved whitespace, block placement, duplicated code and test
interpretation. Longer prompts alone do not let a model inspect its applied edit.
A generic host shell with GitHub credentials would cross the current trust boundary.
Explicit tools reuse the current VM and publisher boundaries without that expansion.
Whole-function and unique-span editing are both available for evaluation; neither
is assumed superior. More calls can increase latency and still fail, so promotion
requires a matched campaign and later held-out evidence, not installation alone.

## Recovery and review

New builds require compatible workers; open histories retain their pinned build.
Cancellation fences future dispatch and awaits local cleanup; already dispatched
remote compute cannot be claimed recalled. Source/tool/skill/config changes create
new identities. Revisit before writable dependencies, arbitrary shell/network,
automatic promotion, changed repository authority or indefinite retention.
