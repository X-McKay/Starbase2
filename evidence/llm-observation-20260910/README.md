# LLM and scoped observation rollout · 2026-09-10

Status: LLM and scoped manual Watchkeeper observation enabled and verified.
GitHub awaits an appropriate repository credential. Existing duties stay paused.

## LLM

[Kubani PR145](https://github.com/X-McKay/kubani/pull/145), merge
`0e273d176a891b4a22bba31aafdf882c55da987a`, enables inference and manual admission
on the existing qualified images from Starbase2 `ef60c6a`. Existing duties remain
paused. Runtime explicitly uses `https://llm.almckay.io/v1` and
`Qwen3.6-35B-A3B-NVFP4`. App-scoped hostAliases routes that hostname to the existing
Traefik Service; TLS hostname/certificate verification remains enabled. Egress
permits only the labelled Traefik pods on the HTTPS target port. Service recreation
requires updating the recorded ClusterIP. Shared DNS was not changed.

The [actual worker observation](llm-enable-worker-verification.json) verified
TLS and model discovery; the [live pod](llm-enable-live-pod.json) was healthy.
One [synthetic review request](request.json) completed through Core and Temporal.
Its [retained advisory](advisory.json) records one provider attempt, 188 prompt
and 85 completion tokens, 1,273 ms, and the expected model. Provider cost was not
reported; this is not a latency benchmark or quality evaluation. The payload
contained normalized synthetic rule codes/meanings and counts, not workspace
source, paths or credentials. Advice remains unverified and does not change
permissions, grading or operational authority.

The [workspace inference denial](workspace-denial.json) returned HTTP409 and
`invalid run configuration`. The first verification assertion expected400; the
API implementation intentionally maps this validation error to409. The actual
rejection was retained without repeating the request.

## Observation boundaries

Watchkeeper preparation follows ADR0005's trust review and accepted ADR0006:
a runtime-only projected service-account token, one namespace's read-only
pod/deployment permissions, explicit API TLS trust and narrowly scoped egress.
It does not mount the operator kubeconfig. Pod API access includes complete
objects at the trusted adapter boundary; retained evidence is normalized.
The two trusted containers share a pod; mount separation is not a sandbox.

GitHub observation requires Contents and Pull requests read-only permission for
private `X-McKay/Starbase2`. The operator's administrator credential is not used
as the runtime identity. No GitHub provider has been enabled.

Memory recall and repairs remain disabled. The existing memory approval endpoint
can still mutate approval records; this rollout makes no claim that every memory
operation is blocked. No memory approvals or graph integration are part of it.

Native UI verification for this rollout remains pending: the existing window
continued showing its earlier retained frame, and UI click control returned
`noWindowsAvailable`. Backend execution evidence does not establish new native
visual acceptance. Owner: Starbase2 world verification. Completion condition:
use the responsive live client to inspect the retained LLM advisory and the
Watchkeeper source/report, confirming current capability state and explicit
namespace coverage.

## First Watchkeeper attempt

[Kubani PR146](https://github.com/X-McKay/kubani/pull/146), merge
`e21e2877b9eddd6874d28a215030979bc359df75`, activated the scoped identity and
manual target. [Actual mounted-identity checks](mounted-identity-status.json)
returned200 for allowed pod/deployment reads and403 for secrets and another
namespace. [Authorization checks](authorization-status.json) denied writes,
logs and exec without attempting those effects.

The [first observation](watchkeeper-failed-01.json) failed honestly before
retaining a source snapshot. The shared adapter incorrectly sent GitHub's media
type to Kubernetes. A [same-token, same-endpoint comparison](accept-header-reproduction-02.json)
reproduced406 with shipped headers and200 with application/json. This is a
connector header bug, not a permission or network-policy failure. No permission
was widened to resolve it. A source correction and newly qualified image are
required before a new observation attempt.


The correction is committed as `028f42a836e93197488580e41d3ceb38af64715c`.
A synthetic HTTP-transport regression reproduced the provider-specific rejection
before the fix and verifies Kubernetes and both GitHub target kinds after it.
All 109 runtime tests passed, plus Ruff formatting/lint and type checks. The
existing Graphiti/Pydantic deprecation warning remains. The [new image qualification](qualification-report.json) passed all16 checks,
including immutable image identity, PostgreSQL/Temporal lifecycle and retained
evidence checks. [Publication](publication.json) binds the verified registry
digests to source028f42a. The [corrected cluster observation](watchkeeper-completed.json) completed
successfully after [PR147](https://github.com/X-McKay/kubani/pull/147), merge
`382dd6caecca01a5aa59a1c34e9918885f7af086`. Its non-synthetic snapshot contains
only the actual pod and deployment in starbase2-prod, with matching report/source
digests. Both containers were ready with zero restarts, and the deployment had
one desired/available replica. No findings under the declared checks is not a
cluster-wide health certification. This observation made no model call.
[Final pod identity](live-pod.json) and [capability/queue observation](after-upgrade-status.json)
bind the successful rollout to the new image pair.


## Handoff and next activation

Manual admission, synthetic inference and the scoped Watchkeeper target remain
enabled. No new recurring duty was added. Memory recall, repairs and legacy
commands remain disabled. Old synthetic target builds remain in historical Core
registration; the current runtime target file contains only starbase2-watchkeeper.
A retained build record alone does not prove current dispatch availability.

GitHub owner: operator credential provisioning, followed by Starbase2 release
verification. Completion condition: a dedicated fine-grained token or GitHub App
credential with Contents/Pull requests read permission for X-McKay/Starbase2,
provided by secure file/secret reference; then scoped GitOps credential/egress
configuration and a bounded manual observation. No administrator credential will
be copied into the worker. Target inference remains off for real provider data.

The base renderer remains conservative; Kubani owns these explicit activation
overlays. Stop through GitOps by disabling admission and pausing duties, then
scale the owned deployment down if needed. Image rollback does not erase retained
histories or evidence. This is still the disposable installation: the separate
durable backup/recovery qualification has not been claimed.
