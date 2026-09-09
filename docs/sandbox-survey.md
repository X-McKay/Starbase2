# Sandbox landscape and local choice

Status: accepted

Surveyed 2026-09-05. Owner: Starbase2 engineering. The decision is scoped to
local, disposable synthetic repair missions, not Kubernetes deployment or
untrusted multi-tenant hosting. Sources below are upstream documentation;
performance and security marketing claims were not treated as measurements.

| Option | Relevant boundary and integration | Decision for this milestone |
| --- | --- | --- |
| [microsandbox](https://github.com/superradcompany/microsandbox) | OCI images in per-sandbox microVMs through libkrun; CLI and SDKs; Apple Silicon and Linux KVM support. No fleet server required. Upstream labels it beta. | Selected. Version 0.6.14 was already installed; a small subprocess adapter reuses its VM, filesystem, network policy, limits, and lifecycle. |
| [CubeSandbox](https://github.com/TencentCloud/CubeSandbox) | Full sandbox platform: API, master, proxy, node agent, networking/egress components, custom VM integration. Linux/KVM emphasis, Kubernetes preview and E2B compatibility work. | Serious deployment candidate; a large operating footprint for two local repair fixtures. Revisit when fleet placement, pooling, or gateway integration earns that complexity. |
| [OpenSandbox](https://github.com/opensandbox-group/OpenSandbox) | Lifecycle and execution APIs, SDKs, Docker/Kubernetes backends, network policy. Stronger isolation depends on configuring an appropriate runtime such as gVisor/Kata/Firecracker. | Useful standard API/platform option. Adds a server and runtime configuration that the current single-host adapter does not need. |
| [Apple container](https://github.com/apple/container) | Lightweight Linux VM per container on Apple Silicon; OCI support. Supported on macOS 26; system service and Swift implementation. | Plausible Mac alternative. Does not supply the Linux deployment path; microsandbox was already usable here. |
| [E2B infrastructure](https://github.com/e2b-dev/infra) | SDK-oriented sandbox platform; self-hosting uses Terraform, with GCP and AWS support documented. General Linux self-hosting is not listed as supported in the README. | Too much cloud infrastructure for this local milestone; no hosted account or paid service introduced. |
| [AIO Sandbox](https://github.com/agent-infra/sandbox) | Browser, terminal, files, editor, Jupyter and MCP bundled in a Docker environment; documented quickstart disables seccomp. | An agent environment rather than the isolation boundary needed here. Its extra tools and interfaces are unnecessary for function repair. |

Maintaining the previous trusted Ruff subprocess remains appropriate for static
analysis that never loads repository code. It is insufficient for executing
model-authored Python. Raw Firecracker/libkrun integration would require Starbase
to own image boot, networking, limits and cleanup; this work belongs in the
existing sandbox project.

## Reproducible local qualification

Installed [microsandbox v0.6.14](https://github.com/superradcompany/microsandbox/releases/tag/v0.6.14)
(release commit `b30fd16`, upstream Apache-2.0) runs on this Apple Silicon Mac.
The Python 3.12.13 Alpine OCI image is pinned by digest in the adapter. Image pulls
are a separate preparation command; missions use `--pull never`. All sandbox
state lives under `.local/microsandbox`, independent of the user's default cache.

[Probe evidence](../evidence/sandbox-qualification/probes.json) records actual
outputs and elapsed time. The probes cover absent host files/credentials/graders,
unprivileged execution, denied core/gateway/public networking, immutable supplied
program, memory/file-size exhaustion, command timeout, background child removal,
and cancellation cleanup. The [crash qualification](../evidence/sandbox-qualification/crash.json)
found the running guest terminated after process-group loss and stopped after
10.83 seconds when only the coordinator died. Earlier failed probes are retained:
`status` can say Running before an agent endpoint exists, and Crashed is a
terminal state distinct from Stopped. The corrected probe first proves guest
reachability and refreshes liveness with ping. These probes do not prove resistance to kernel,
hypervisor, image parser, or runtime vulnerabilities. Arbitrary hostile
multi-tenancy and production credentials remain outside the qualified scope.

The adapter pins one CPU, 256 MiB RAM and root disk, 16 MiB temporary filesystem,
32 processes, 64 open files, 128 MiB address space, 8 MiB files, 32 KiB output per
stream, ten-second command and thirty-second VM lifetime. No host mounts,
forwarded ports, vsock endpoints, injected secrets, or guest networking are used.
Only the supplied program and ordinary interpreter image enter the VM. The core
and grader remain outside; returned stdout is untrusted data.

## Exit and review triggers

The adapter's input is a bounded Python program and output is an execution
observation. Replacing its implementation does not change Temporal history or
progression semantics, but changes the immutable build and requires new boundary
qualification. Revisit the choice for Linux architecture/image support,
concurrent throughput, runtime security releases, fleet scheduling, and Kubani
network/identity requirements. Do not infer Kubernetes readiness from this Mac
experiment.

## Field-agent follow-up qualification

The 2026-09-06 [Darwin-host run](../evidence/sandbox-qualification/darwin) repeats
the Linux guest probes with a real temporary host-only canary and explicit
credential-variable exclusion. Isolation, resource bounds, timeout, background
cleanup, cancellation and both coordinator-loss cases passed. The separate
Linux host has usable KVM and the pinned archive passed its upstream checksum,
and on 2026-09-07 the [Linux-host run](../evidence/sandbox-qualification/linux)
passed the same probes and crash cases on x86_64 KVM once the image pin named the
x86_64 manifest digest; the pinned digest recorded on the Mac was the arm64
manifest of `python:3.12.13-alpine`, so the adapter now pins one digest per
architecture and refuses unknown architectures. Kubernetes qualification must not
be inferred from either host. Read-only field agents do not execute candidate
code in either case.
