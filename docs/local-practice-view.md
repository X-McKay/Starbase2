# Local practice in the native client

Status: proposed

## Operator journey

Open **Work [J] → Practice**. The native Godot panel follows the bounded learning
contract in [ADR 0010](adr/0010-local-developmental-learning.md). Core owns
curriculum selection, immutable Procedure candidates, paired trials, comparison
and practice adoption. The client displays records and submits explicit operator
commands; it does not train, grade or qualify an agent itself.

For an unconfigured duty, select an exact registered `joint-readiness-v1` build.
**Enable practice duty** sends generation zero, or the current duty generation
plus one for an existing duty. Existing duties use the current practice incumbent,
not the older baseline recorded on the previous duty. The default admits at most
two cycles, with a 60-second cooldown. Each cycle reserves one 32,768-token proposal
and eight 384,000-token public trials: up to 3,104,768 tokens reserved per cycle.
Reservations are distinct from actual consumption. The panel shows the frozen
settings rather than claiming an estimated cost or a token efficiency score.

**Stop practice duty** and **Cancel cycle** remain outside the detail scroll.
Stopping uses a separate command channel and works when installation admission is
disabled. Duty stop blocks further dispatch in active and future cycles; Core stop
recovery cancels active cycles and admitted children while retaining late accounting.
It does not claim that already-started calls were undone. Individual cycle cancellation
requires its own retained cancelled or explicitly already-terminal receipt. A
pending initial enable can be reconciled before submitting the requested stop.
Model animation never gates these controls.

When the duty is stopped, select a registered replacement and use **Change stopped
baseline**. This is a separate generation update and leaves the duty stopped.
The panel requires terminal retained cycles; Core additionally checks outstanding
claims and all policy conditions. Core preserves old cycles and records a rebase
receipt. Enable remains a separate action with another generation. A baseline
change transfers no prior qualification or XP.

## Evidence and compatibility

The selected cycle exposes exact baseline and candidate digests, Trainer proposal
state, retained outcome, paired pass counts, hard gates, every trial mission ID,
public scenario and recorded accounting. An absent trial result says outcome not
reported; it is not shown as a pass. `practice-adopted` means local public practice
only, with no operational qualification or XP. The exact-record disclosure includes
the control/rebase history and selected cycle. Public diagnostic outcomes cannot
establish service recovery or production readiness.

The optional `GET /v6/snapshot` polls only while visible, with an eight-second
request bound, no redirects and a 2 MiB body limit. Initial/stopped baseline choices
come from the existing V5 registry. A V6 404 suppresses automatic retries until
Refresh; unavailable, malformed or stale evidence remains visibly last-known.
The 30-second freshness bound uses the client's successful receipt time because
V6 does not provide a snapshot observation timestamp. Endpoint changes fence old
callbacks, and acknowledged writes cancel in-flight older snapshot reads.
Unsupported cycle rows disclose incomplete coverage. Fixtures never poll or write.

Duty, stop and rebase acknowledgements compare the entire normalized duty payload,
including generation, baseline, limits and all budget integers. A lost reply leads
to GET reconciliation, not another POST. A conflicting newer generation cannot
acknowledge the requested change. Likewise, a same-ID evaluating cycle cannot
acknowledge cancellation. Unknown effects block endpoint changes and further
admission. Session/Cookie/Origin handling reuses the existing operator client;
worker credentials are never read or sent.

Identity and uncertain commands survive hiding the panel but are currently held
in memory. This slice does not claim a durable client command journal across app
restart; retained Core records and independent API controls remain the recovery
source. Stop requests need a fresh control generation for compare-and-swap. Core
is the final authority when a generation or incumbent changes during the request.

## Verification and release boundary

`test_learning_panel.gd` covers fixture isolation, current-incumbent generation,
integer budget display, eight trial identities, unavailable/malformed/stale data,
compact keyboard disclosure and stopped-baseline selection. Run it natively with:

```sh
mise exec -- godot --resolution 1280x800 --path apps/world --script test_learning_panel.gd -- --capture=/tmp/starbase-practice-review
mise exec -- python scripts/check_world_learning.py
```

The tracked HTTP fixture injects lost replies for enable, stop, cancel and rebase,
with stale/conflicting reconciliation responses before the exact record. Exactly
four intended POSTs occur; retries are reads. It checks numeric JSON integers,
operator session/Origin, separate enable after rebase, and stop with admission off.
`just check-world` runs this and the V5 action fixture. Native 1280×800 and 800×640
large-text captures are retained in [practice evidence](../evidence/world/learning-ui-20260928/README.md).

These are synthetic UI and protocol checks. Real inference cycles, packaged
artifacts and integration belong to the parent delivery gate; these captures do
not claim owner visual acceptance, performance improvement, screen-reader support,
production readiness or Kubernetes/Flux deployment. Removing this panel and its
operator adapter rolls back client functionality without altering retained Core
learning records. Core/database rollback follows ADR 0010.
