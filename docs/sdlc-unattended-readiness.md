# Unattended SDLC readiness

Status: accepted local implementation, 2026-09-28. Owner: Core/runtime.

`starbase_runtime.sdlc_readiness.assess` evaluates an authoritative snapshot and
fresh trusted observations. Its report is advisory and cannot grant publication
permission. Core policy and fresh effect authorization remain mandatory. An open
admission circuit must stop new work while leaving reconciliation, cancellation,
and already-authorized recovery available.

The default circuit stops admission at three consecutive retained failures,
32 queued missions/verifications, 100 missions, 256 discoveries, 16 verifications
or feedback records for a PR, an exhausted policy-generation mission budget,
a disabled/expired policy, a recent trusted provider/inference outage, or retained
claims on blocked/failed/cancelled work. A claim is possible external activity,
not proof that the effect failed. This conservative report requires inspection of
those effects; it must not trigger a blind retry or silently delete retained data.

Qualification is a separate result. Sandbox readiness needs fresh trusted facts
for the evaluated build, executable controls, backup/restore and independent stop
verification. Draft-PR readiness additionally needs publication policy and a
verified dedicated GitHub identity restricted to the exact policy repository.
Facts have `{value, observed_at}` shape and expire after five minutes by default.
Missing, future-dated and stale evidence remain unknown. An operator may collect
fresh attestations of durable qualification evidence; an agent cannot issue them.
No successful local simulation qualifies the current model build.

Creating and installing the GitHub App requires the repository owner's account.
Install it only on the authorized pilot repository with the minimum observation,
branch/PR and status permissions actually required by the trusted adapters. Keep
installation tokens in the trusted service, outside prompts and candidate VMs.
Until those identity facts are verified, the readiness report cannot mark draft-PR
operation ready. This implementation does not provision the App or activate the
live monitor.

## Executable failure controls

After building Core, run:

```bash
PYTHONPATH=services/runtime .venv/bin/python scripts/sdlc_resilience_integration.py
```

The script creates an isolated Core database and uses real runtime activities,
feedback classification/retention/admission, and the trusted publication adapter.
Model outputs, VM observations, and GitHub transport are synthetic. No GitHub
credentials, model requests, repository execution or live writes occur. It checks:

- stale/conflicting feedback cannot admit work; current exact-head feedback is
  retained and copied into a new verification;
- a status written before its response is lost is reconciled with exactly one
  provider write and one Core claim;
- cancellation fences subsequent effects without erasing the started claim;
- concurrent head drift after the effect claim prevents the provider write;
- cancellation while model and sandbox adapters are outstanding prevents later
  handoffs and mission progress.

Fresh `.local/sdlc-resilience-integration-*` directories preserve the harness,
fixture, Core log, event results and final snapshot. A failed control stops and
remains retained. These controls exercise trusted adapters and Core directly;
they do not claim Temporal interruption/replay, host reboot, actual subprocess termination,
long-duration service health or general provider-outage recovery. The separate
Temporal integration controls remain necessary. Local readiness unit tests also
cover saturation, repeated failures, freshness and overbroad identity scope.
