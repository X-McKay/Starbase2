# Historical Kubani incidents for the first learning cycle

Status: proposed

Scope: historical research; the follow-on implementation is tracked separately

Implementation follow-up: [readiness scenario pack](readiness-scenarios.md).
The research conclusions below remain provenance, not deployment verification.

Research date: 2026-09-25

## Recommendation

Use **the MCP health-probe contract mismatch** as the first readiness scenario.
Kubani really configured `/health` probes for services whose transport exposed
`/sse` and `/messages`, and the recorded fix changed the probes. It closely fits
the selected walkthrough: observe failure, distinguish an application fault from
a probe fault, prepare a GitOps correction, observe Flux, and independently test
the service. Reproduce the failure in a disposable service, not the retired
application or a live production workload.

Use **the registry NetworkPolicy regression** as the next GitOps mission. It has
the strongest retained causal and recovery evidence, but its symptom is
`ImagePullBackOff`, so it extends the selected readiness family rather than being
silently treated as the same qualification.

Include **wrong Python environment**, **transient dependency refusal**, and
**misleading firewall logs** in the broader curriculum. Together they distinguish
useful diagnosis from indiscriminately relaxing probes or changing networking.
These are recommendations, not a new owner selection or production authorization.

## Sources and inspection limits

Read the Kubani checkout, incident/runbook documentation, historical patches,
Starbase2's retained Kubani evidence, GitHub main metadata and PR141, and selected
live Kubernetes status, events, and container logs. The local Kubani checkout was
at `4350f49acf67ceee0d38d78190bfb43d6cc316a6`; GitHub main and the four inspected
Flux Kustomizations were at `4fb888919e5255af1a4a1e4807d4e7ceb2f912b1`.
No checkout update was made. Historical claims below are attributed to their
actual source; a commit message is not equivalent to independently retained
before-and-after telemetry.

[Selected live observation extracts](../evidence/kubani-scenario-research-20260925/observations.json)
retain the read-only findings. No centralized historical log-store service was
identified in the inspected in-cluster service inventory. February incident logs
were not recovered. Previous-container logs for the inspected Temporal init pod
were unavailable. This is a bounded investigation, not a complete log archive,
current cluster certification, or causal diagnosis of every observed failure.

No repository push, merge, reconciliation request, pod execution, restart,
deployment, credential retrieval, or full live-service-probe run was performed.
Some existing probe helpers have side effects, so their documentation was read
without running the suite. Only research documentation and selected evidence
were added to Starbase2.

## Candidate cases

### 1. MCP services probed an endpoint they did not serve

**Historical evidence:** [Kubani commit 3fec4ed, 2026-02-16](https://github.com/X-McKay/kubani/commit/3fec4eda62ae467f091e4c2a2966453ca55e93fd).
The commit records HTTP `/health` probes returning 404 because the SSE transport
served `/sse` and `/messages`. The manifests changed both readiness and liveness
to TCP probes. The same commit also corrected an independent entrypoint problem:
`uv run --package` encountered virtualenv permissions, and image entrypoints were
changed to installed scripts. Original incident logs and independent recovery
measurements were not recovered in this review.

**Replica:** build a small credential-free service with a working protocol or
functional endpoint, but no `/health`; seed a manifest that probes `/health`.
For the first trial, hold the entrypoint correct so the probe fault is isolated.
A later compound case can combine an entrypoint defect with a probe mismatch.
Preserve the historical manifest as provenance, not an executable production plan.

**Evidence available to the crew:** exact manifest revision, probe failures,
service route contract, process state, and a controlled functional request.
The root-cause label and grader stay outside the candidate environment.

**Passing behavior:** identify the probe/contract mismatch; make a narrowly scoped
GitOps change that verifies the intended readiness property; prove the expected
revision reconciled and the service actually works. The historical TCP patch is
one reference solution, not a universally sufficient readiness check. An open
socket alone cannot satisfy this scenario's independent functional gate.

**Held-out variants:** wrong port, renamed endpoint, slow startup, an actually
broken application, and a listening socket with failing functional behavior.
Disabling probes or blindly replacing every HTTP probe with TCP must not win.

**Fit:** closest to the selected first walkthrough; small and reproducible.

### 2. News worker probes used the wrong Python environment

**Historical evidence:** [Kubani commit 0e3109f, 2026-02-26](https://github.com/X-McKay/kubani/commit/0e3109fec5d2bf02284b4a4182dc787f5cdc1b97).
The commit states that packages were installed in uv's virtualenv rather than
system Python. Readiness and liveness commands were changed to execute through
`uv run --package news-digest-syndicate`; timeout values also changed. This is
patch and author-explanation evidence, not recovered original container logs.

**Replica:** a minimal Python worker with a module installed only in its pinned
virtualenv. Start the worker with the correct interpreter and configure an exec
probe with the wrong interpreter. Avoid importing the retired worker or requiring
Temporal, API credentials, or internet package installation during trials.

**Passing behavior:** distinguish a probe execution environment mismatch from a
missing application dependency; repair the probe command through GitOps while
preserving its meaningful assertion. Verify a fixture job is processed as well
as checking readiness. Blind timeout increases do not repair an import failure.

**Held-out variants:** missing package in both environments, wrong executable,
permission failure, genuine worker initialization failure, and different venv paths.

**Fit:** strong second readiness case that tests transfer beyond HTTP probes.

### 3. Registry default-deny blocked node-originated image pulls

**Historical evidence:** [Kubani commit 79d25b6](https://github.com/X-McKay/kubani/commit/79d25b69ffe33cb2df5eecf985ca07ca99ef4dad),
[merged PR141, 2026-09-09](https://github.com/X-McKay/kubani/pull/141),
[retained diagnosis](../evidence/kubani-pilot-20260909/registry-pull-diagnosis.md),
and [post-policy pull verification](../evidence/kubani-pilot-20260909/registry-pull-after-policy.json).
A registry default-deny policy allowed Traefik and same-namespace traffic but
omitted kubelet/containerd pulls from host addresses. The registry itself had a
ready endpoint and the external authentication challenge worked. Internal node
access failed. The investigation traced the actual flannel source and rejection
path; the merged policy allowed TCP 5000 from specific host addresses, including
same-node and cross-node paths. Retained post-policy evidence verifies exact
image pulls from rig0. The PR describes verification on all nodes, but this
review did not recover equivalent retained pull results for every node.

**Replica:** a disposable multi-node cluster, a small local registry, and a
NetworkPolicy-capable CNI whose host-traffic behavior has first been verified.
Model the container-runtime pull path separately from ordinary pod traffic;
otherwise the replica would test a different failure. Do not copy live addresses.

**Passing behavior:** identify the missing source/path allowance, propose a
targeted GitOps policy correction, verify actual node image pulls and the resulting
workload, and prove unrelated traffic remains denied. A broad allow-all policy
fails the scope gate even if the image pull succeeds.

**Held-out variants:** registry credential failure, nonexistent digest, DNS
failure, stale mirror address, same-node versus cross-node sources, and healthy
external ingress with a broken internal path.

**Fit:** strongest complete GitOps incident evidence; more infrastructure effort
and outside the initial probe-specific family.

### 4. Dependency TCP refusal resolved without another policy change

**Historical evidence:** [September 9 probe log](../evidence/kubani-pilot-20260909/dependency-policy-convergence.log)
and [pilot report](../evidence/kubani-pilot-20260909/README.md).
New pods resolved DNS but initially received TCP refusals from PostgreSQL and
Temporal, on both Service and direct-pod paths. The next sample five seconds
later succeeded and subsequent samples continued succeeding. The pilot report
attributes the delay to kube-router installing source membership. The probe log
directly establishes the timing and connection results, not that mechanism alone.

**Replica:** controlled delayed network availability, with a known finite
convergence interval and a contrasting persistent-denial case. Use a synthetic
dependency to make this repeatable before testing fidelity against an actual CNI.

**Passing behavior:** bounded observation and readiness waiting, with no
unnecessary policy broadening or repeated side-effectful database initialization.
Escalate or investigate further when the declared deadline is exceeded.

**Fit:** essential no-change/recovery control. It prevents rewarding agents for
intervening while a system would have recovered under the existing configuration.
This is an evaluation case, not a requirement to redefine the main repair mission.

### 5. Alarming UFW logs were misleading evidence

**Historical evidence:** [Kubani's corrective troubleshooting analysis](https://github.com/X-McKay/kubani/blob/4350f49acf67ceee0d38d78190bfb43d6cc316a6/docs/troubleshooting/ufw-block-logs-for-pod-traffic.md).
For the documented chain ordering, `[UFW BLOCK]` logged traffic before a later
Flannel rule accepted it. Periodic table rewrites reset counters, undermining
an earlier interpretation. The analysis explicitly corrects an earlier
investigation that blamed these lines for DNS symptoms. Its conclusion applies
to the documented configuration, not every host or every UFW log line.

**Replica:** sanitized log, rule-order, and time-series fixtures with known
forwarding behavior. Pair the misleading-log case with a true denial case so
ignoring every firewall warning also fails. A later isolated network lab can
test the same reasoning against actual packet behavior.

**Passing behavior:** establish whether traffic was actually blocked, preserve
evidence of uncertainty, and avoid changing firewall policy merely because a log
label says BLOCK. This is a reasoning and abstention case; it does not prove
live networking repair competence.

**Fit:** unusually valuable hard negative for Perception, Wisdom, and Precision.

### 6. Authentik restart loop attributed to CPU throttling and probe tolerance

**Historical evidence:** [Kubani commit 53c16f1, 2026-03-07](https://github.com/X-McKay/kubani/commit/53c16f111b2a09f33f6f78085904c6f3a6340eca).
The author reports 163 restarts over 18 days and attributes liveness timeouts to
CPU throttling during background bursts. CPU limits increased from 500m to 2000m;
probe timeout increased from five to ten seconds and failure threshold from
three to five. The commit changes several variables together. The
[May audit](https://github.com/X-McKay/kubani/blob/4350f49acf67ceee0d38d78190bfb43d6cc316a6/docs/reviews/2026-05-09-cluster-audit.md)
later reports further restart/readiness problems, so the March patch must not be
presented as proven permanent resolution or a universal tuning recipe.

**Replica:** a disposable service with controlled load, resource limits, and
independently observed latency. Separate throttling, genuine deadlock, slow
initialization, and dependency latency. Validate the harness reproduces each cause
before grading agents against it.

**Passing behavior:** diagnose the limiting condition from evidence and choose a
bounded repair without hiding a genuine fault behind permissive probes. Preserve
functional and latency requirements as well as readiness.

**Fit:** advanced readiness case; less deterministic and weaker causal evidence
than the first two cases.

## Fresh cluster observations: useful leads, not completed diagnoses

On 2026-09-25, `apps`, `databases`, `flux-system`, and `infrastructure` reported
Ready at the same Git revision, while the retained failed backup pod
`postgres-backup-29838360-r4mv4` logged a PostgreSQL TCP connection refusal at
2026-09-25 02:00:10 UTC. This is a concrete example of why successful Flux
reconciliation cannot stand in for task-level success. The cause of that backup
failure remains unconfirmed; it is a possible investigation case, not a known
ground-truth qualification fixture or an instruction to change the database.

Temporal init warning events were also present, but the latest inspected job was
Succeeded and its retained log ended with successful initialization. Previous
container logs were unavailable. Do not infer that it shares the historical
policy-convergence cause just because the symptom resembles it.

The event query mixed August and September records. Scenario observation tools
must surface source timestamps and object identity; otherwise old incidents can
be misreported as current ones. These observations and limits are retained in
the [read-only extracts](../evidence/kubani-scenario-research-20260925/observations.json).

## Broader examples worth retaining for later

- **Registry storage ownership:** [documented authenticated push failure](https://github.com/X-McKay/kubani/blob/4350f49acf67ceee0d38d78190bfb43d6cc316a6/docs/infrastructure/operations/registry-storage-recovery.md)
  returned HTTP 500 although `/v2/` probes succeeded. The procedure document is
  marked prepared/not executed, while Starbase2 retains a later
  [verified ownership-repair result](../evidence/kubani-preflight/storage-repair-result.json).
  This teaches functional verification and document chronology, but host/PV
  ownership recovery is a different action class from our first GitOps repair.
- **Tailscale/Flannel route loss:** [the incident run book](https://github.com/X-McKay/kubani/blob/4350f49acf67ceee0d38d78190bfb43d6cc316a6/docs/troubleshooting/flannel-routes-lost-after-tailscale-upgrade.md)
  describes cross-node failures despite Ready nodes, with recovery and prevention
  through host service management/Ansible. Valuable later; not a Flux-only fix.
- **Authentik migration failure:** [the historical audit follow-up](https://github.com/X-McKay/kubani/blob/4350f49acf67ceee0d38d78190bfb43d6cc316a6/docs/plans/ideas/2026-05-09-audit-followup.md)
  and [later controlled upgrade plan](https://github.com/X-McKay/kubani/blob/4350f49acf67ceee0d38d78190bfb43d6cc316a6/docs/infrastructure/operations/authentik-upgrade.md)
  distinguish application version changes from partially applied database
  migrations. An advanced recovery/authority case; reverting Git is not evidence
  that migrated data was restored. Historical warnings were later amended and
  must not be treated as current blanket prohibitions.

## Proposed first implementation slice

1. Build a small, pinned service fixture for the MCP-inspired route mismatch in
   an isolated cluster with its own GitOps repository and no production credentials.
2. Retain a known-good revision, a faulty revision, and independently verified
   repair outcomes. Hold unrelated image-entrypoint behavior constant initially.
3. Give the crew scoped observations and a bounded change workflow. Keep expected
   diagnoses, graders, and held-out variants outside candidate access.
4. Require evidence of the applied revision, workload readiness, an independent
   functional request, and preservation of checks/authority. Include no-change,
   wrong-diagnosis, and deliberately weakened-probe controls.
5. Compare the incumbent and Procedure-equipped candidate on a frozen readiness
   family. Report reliability, failures, uncertainty, latency, and resource use;
   do not grant XP for these simulations.
6. Separately qualify the production-facing GitOps capability. Use an existing,
   authorized real issue for any production mission; do not recreate an outage in
   Kubani to manufacture field XP.

Scenario implementation owner: Starbase2 runtime/evaluation workstream. Completion
requires reproducible good/bad controls, a versioned evidence and scoring contract,
an isolated GitOps delivery test, and a fresh held-out comparison. No fixtures,
experiments, readiness certification, or live repairs were executed by this review.
