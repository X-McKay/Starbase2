# GitHub fleet monitoring

Status: accepted

Implemented and activated locally; initial account acceptance is recorded in
[fleet evidence](../evidence/repository-fleet-20260928/live-acceptance.json).

Starbase can discover and watch repositories owned by `X-McKay` that its configured
GitHub identity can access. Discovery checks the authenticated account identity,
then pages its owned repositories. This includes accessible private repositories;
it does not claim visibility into repositories excluded by credential permissions,
repositories owned by another account, or organization repositories merely shared
with the account. There is a hard capacity of 256 non-removed watches.

## Observation and authority

Each observation captures bounded repository metadata, the default-branch revision,
recent open issues, Actions runs at that revision, and open pull requests. At most
30 recent issue entries (which can include PRs), 30 Actions runs and ten recent
open PRs are inspected. Changed Python blobs receive the existing pinned Ruff
checks, Git identity verification and source masking; other languages are not
reviewed by that analyzer. The latest run per workflow is retained within the
observed revision/window. Missing runs, inaccessible endpoints, rate limits and
truncated coverage remain unknown or partial, never a healthy certification.

The output is local evidence and advisory findings: failing CI, review candidates,
and configured-rule warnings. An open non-draft PR is a candidate to inspect,
not proof that no reviewer has already reviewed it. No GitHub comments, issues,
reviews, commits, merges, branch changes or repository modifications are sent.
Observation does not automatically create a repair mission, award XP or authorize
an agent to change a repository. The native repository view and structured evidence
remain projections of Core records.

## Enrollment, timing and recovery

Discovery defaults to once per hour; newly enrolled watches default to a 900-second
observation interval. The discovery configuration permits 300–86400 seconds for
each interval. Discovery failures retry after 300 seconds while retaining the last
successful inventory. A complete inventory atomically enrolls previously unseen
repositories and advances its checkpoint. Exact checkpoint retries are idempotent;
stale/conflicting checkpoints, wrong owners and capacity overflow are rejected.
Partial inventory never enrolls a partial set.

Rate-limit responses establish a process-wide GitHub cooldown. Subsequent reads
fail before network I/O until the bounded retry/reset deadline. Missing coverage
remains visible; there is no overnight API-budget qualification yet.

Existing watch controls win over discovery. Paused or removed watches stay paused
or removed; their generation and interval are preserved. A repository disappearing
from inventory is not automatically deleted or disabled. Remove retains a tombstone
and past evidence, and restore reuses the watch identity. Pause/remove stop future
admission; already queued or running observations require a separate stop.

Repository timers use stable staggered phases and Core admits the oldest due
repository watches first. Twenty active field runs and twenty individually
configured duties remain separate limits; increasing fleet capacity does not
increase concurrent work. Busy targets skip ticks, and missed intervals do not
accumulate a catch-up queue. Temporal timers, Core admissions and discovery
checkpoints survive process restarts. Old V4 histories retain their command order
through a workflow patch. Fairness does not promise a completion deadline when
providers, workers or shared run capacity are unavailable.

Every watch has its own compact `latest_run`, independently of the global 120-run
snapshot window. An old observation can therefore remain visible without appearing
fresh. No run is automatically deleted by this response window.

## Local configuration and credentials

The worker reads `STARBASE_GITHUB_DISCOVERY_FILE`, an operator-owned JSON file:

```json
{
  "owner": "X-McKay",
  "token_file": "/absolute/private/path/github-read-token",
  "interval_seconds": 900,
  "discovery_interval_seconds": 3600
}
```

Core independently requires `STARBASE_GITHUB_DISCOVERY_OWNER=X-McKay`; a valid
worker token alone cannot authorize enrollment for another owner. GitHub requests
use the fixed API origin, verified TLS, bounded responses and timeouts, and no
redirect following. Credentials are read only by the trusted provider adapter;
they are excluded from builds, retained source, reports, model inputs and native UI.

Prefer a fine-grained credential granting metadata, contents, issues, pull requests
and Actions read access to the intended repositories. A pre-existing GitHub CLI
OAuth credential can carry broader authority; read-only adapter behavior does not
reduce that credential's underlying permissions. When explicitly using that local
identity, obtain it through the existing local keyring/CLI and place only the
necessary credential in an ignored, private file with mode `0600`, under a private
`0700` directory. Never print it, commit it or place it in a command argument.
Rotate/revoke the provider credential independently of stopping Starbase.

## Detached local monitor

The local supervisor uses `.local/github-monitor/discovery.json`, a matching
credential file, and the existing worker credential at `.local/runtime-token`.
It starts loopback Core at `127.0.0.1:8787` and a dedicated Temporal development
server at `127.0.0.1:7244`, with its own task queue. It backs up the local Core
SQLite database before startup and refuses occupied ports instead of taking over
another process. Its local profile disables inference, repairs, joint missions,
learning, memory and the legacy fixture API.

From the repository root, with the locked environment and built binaries:

```sh
mise exec -- .venv/bin/python scripts/github_monitor.py start
mise exec -- .venv/bin/python scripts/github_monitor.py status
mise exec -- .venv/bin/python scripts/github_monitor.py stop
```

The supervisor owns only its recorded processes, verifies process identity before
stopping them, and stores local logs/state under `.local/github-monitor`. `status`
reports owned process liveness and the accessible Core snapshot; process liveness
alone is not successful provider observation. Closing the terminal does not stop
the detached supervisor. No login item or automatic startup is installed. Work
pauses when the Mac sleeps or loses connectivity and requires starting the monitor
after reboot. If an owned service exits, the supervisor stops its remaining
children in reverse dependency order, then restarts the group against the same
persistent Core and Temporal stores. Transport probes check Temporal's listener
and Core's snapshot endpoint every five seconds; three consecutive unsuccessful
probes trigger the same recovery. An individual failed probe is retained without
immediately restarting healthy processes. Worker liveness is checked, but this
is not a worker-progress watchdog or proof of provider success.

Recovery is bounded to three restarts per supervisor invocation, with interruptible
two-, four-, and eight-second backoffs. The budget does not reset after a quiet
period. Exhaustion stops all owned children and reports `failed`; an operator must
inspect the retained logs and explicitly start a new invocation. `status` exposes
`starting`, `running`, `recovering`, `stopped`, or `failed`, the last timestamped
transport probe, restart count/limit, and bounded failure history. Every restart
rechecks the listening ports; a new unrelated occupant is never stopped. Explicit
`stop` interrupts backoff and prevents further dispatch. Recovery does not renew
policy expiry, alter credentials, retry GitHub effects outside their durable
workflow claims, or increase mission authority. The supervisor itself has no
crash/reboot recovery service.
This is a local development installation, not Kubernetes deployment
or an always-on production service.

## Verification and remaining qualification

The discovery checkpoint adds SQLite schema version 8 and PostgreSQL migration
version 6. SQLite upgrade/reopen and atomic enrollment were tested, and the local
supervisor takes a consistent backup before startup. Older Core binaries reject
newer schemas; binary rollback alone is insufficient after this migration.
PostgreSQL migration and updated application grants have not been exercised on a
live database in this slice. No Kubernetes/Flux rollout was performed.

[Repository fleet evidence](../evidence/repository-fleet-20260928/README.md) records
capacity, fairness, owner/credential fencing, migration, atomic enrollment, replay,
and synthetic HTTP integration checks. Separate live acceptance records the
initial 44-repository sweep, bounded coverage and successful monitor restart.
This does not establish overnight provider reliability or API-budget endurance.

The run ledger currently has no automatic retention cap. Its latest-run and
fairness queries scan retained history, so the bounded snapshot does not bound
storage or long-term query cost. The [delivery plan](autonomous-rpg-delivery.md)
owns retention/indexing qualification before an unattended long-duration claim.

The optional [algent SDLC pilot](repository-sdlc-pilot.md) now adds a separate,
explicitly authorized write capability. With private `sdlc.json` present the
supervisor enables local inference and V7; the existing fleet watches remain
observation-only. Its migration advances SQLite to 9 and PostgreSQL to 7.


Independent algent PR verification is a second explicit opt-in via private
`verification.json`; it does not change the 44 repository watch definitions or
grant them write authority. It publishes its own exact-commit status and can
correct the retained pilot branch under the existing policy. See the
[verification contract](repository-sdlc-pilot.md#independent-verification-and-pr-correction).


The bounded supervisor recovery is covered by deterministic lifecycle tests for
child failure, startup health, repeated versus transient probe failures, restart
exhaustion, stop during backoff, and an unrelated process occupying a released
port. These tests do not qualify unattended live endurance. A dedicated GitHub
App with narrow repository permissions still requires owner-account provisioning;
the supervisor does not create an App or narrow the underlying CLI credential.
