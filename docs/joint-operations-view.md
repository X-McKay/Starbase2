# Joint operations in the native client

Status: proposed

## Implemented mission journey

Open **Work [J] → Joint operations**. The native Godot workspace reads the
[durable readiness ledger](joint-readiness.md) through `GET /v5/snapshot`.
Review, Compare, Duties and History keep their existing tab indexes and controls.

The view exposes the selected mission's exact ID, opportunity, immutable build,
scenario, state, timestamps, deadline, diagnostic outcome and recorded reason.
It shows the mission lead, workload specialist and service specialist only when
Core has recorded their member tasks. A task's recorded round, question, focus,
token grant, dispatch/reply state, accounting and typed findings explain the
handoffs. Roles do not invent persistent crew members or move existing actors.

Shared request/token reservations and conservative token accounting remain
separate. An absent reply is unknown; an accepted reply is eligible for diagnostic
grading, not proof of task success. The final decision and expandable exact record
retain source IDs, observations and traces from the snapshot. This first view
uses the complete mission records already included in the snapshot; it does not
claim a paginated history or separately fetch `/v5/missions/{id}`.

The endpoint is a public simulation under
[ADR 0009](adr/0009-durable-readiness-coordination.md). A diagnostic pass is labeled
as a simulated diagnosis. It does not imply service recovery, cluster changes,
XP, qualification or production readiness. Mission launch and cancellation now use the existing local operator session and
Origin boundary. The read-only Trainer review mode remains separate from work
admission. Independent operator/API controls remain available outside the renderer.

## Transport and presentation boundaries

The optional endpoint is polled every three seconds only while this tab is
visible, with one bounded eight-second request and redirects disabled. Preview
fixtures never poll. A 404 reports that Joint operations is unavailable on that
Core and stops automatic requests until explicit Refresh or an endpoint reset.
A failed or malformed response retains the previous records with explicit
last-known/unknown status. Reconnecting to another endpoint clears retained data
and fences callbacks from the previous connection. Older snapshot observations
cannot replace newer retained state.

The UI marks missing, future-skewed or older-than-30-second observation timestamps
stale. This is a client display freshness bound, not evidence that a member failed.
Queued, running, failed, cancelled and unknown states remain distinct. Unsupported
mission rows disclose incomplete coverage rather than silently implying an empty
or complete ledger. Repeated unchanged polling preserves selected identity and
keyboard focus.

The legacy operations briefing counts its own snapshot; it is hidden in the Joint
operations tab so it cannot imply a count of V5 missions. Mission selection and
Refresh remain above the scrollable detail. Keyboard users can focus details and
use Page Up, Page Down, Home and End, then reveal the exact record with Enter.
The compact view preserves the close action, tabs, selected mission and a readable
detail area with larger text. This static view adds no operational animation.

## Verification and remaining work

Focused UI checks cover identity selection, member replies, grants and diagnostic
semantics; 404, malformed replies, stale data and endpoint callback fencing;
fixture/hidden polling suppression; keyboard scrolling and record disclosure;
and compact detail space. A loopback HTTP fixture observed exactly three GETs
(valid snapshot, 404, explicitly retried malformed reply) and zero mutations.
Existing Operations and Ember Operations checks passed. Native source-checkout
captures at 1280×800 and 800×640 with larger compact text were inspected; failures
and corrections are retained in [local evidence](../evidence/world/joint-operations-20260927/README.md).
The parent task owns integrated world verification.

No live model run, production source, standalone export, screen-reader support,
performance improvement or owner visual acceptance is claimed by these captures.
Authenticated launch/cancel and reconciliation are implemented below. A qualified
physical mission journey still depends on authoritative crew identities; the
current structured roles do not claim that binding. Parent world delivery owns
that gate and standalone export verification.

## Proposed Trainer reviews

The view selector inside Joint operations switches between **Missions** and
**Trainer reviews** without dispatching work. The additive `opportunities` field
in `/v5/snapshot` supplies Core-derived groups of failed or unresolved diagnostic
missions. Every displayed proposal retains its exact build, scenario, stable
review ID, category, observed count, most recent source time, proposed
investigation, and source mission/task identities. The ordering is by stable
identity and is explicitly not a priority ranking.

Only the declared public-simulation review scope, proposed-review status and
known Core categories are rendered as proposals. Unknown categories disclose
incomplete coverage. The UI never derives a category from a model's prose.
A proposed review is labeled **training not started**, with no qualification, XP
or adoption. Selecting it is an inspection action, not a training reservation,
candidate creation or campaign launch.

Group and source token accounting remain visible, including uncertain usage
that may consume full grants. If Core reports aggregate arithmetic overflow,
the aggregate is unavailable while exact per-source amounts remain readable.
The UI does not convert absent or overflowed usage to zero. An older payload
without `opportunities` says Trainer opportunities are not reported; a present
empty array says no proposed reviews are present in that snapshot. Disconnect
and stale observation labels qualify retained proposals as last-known.

The existing keyboard scroll and exact-record disclosure work for proposals.
Mode switching retains the selected mission separately from the selected review.
Focused checks, native wide/compact captures and the GET-only loopback fixture
passed; [Trainer review evidence](../evidence/world/trainer-reviews-20260927/README.md)
retains the new source hashes and captures without replacing the earlier mission
review evidence. No automated Trainer execution is implemented by this UI.


## Local mission actions and presentation choices

Select **Launch mission** to choose a registered immutable build and one of the
four public scenarios. The build supplies its inference mode; the form identifies
scripted controls versus model inference, exact digest, shared request/token
limits and ten-minute Core deadline. Budget inputs must be whole values within
the Core contract. Preview fixtures cannot dispatch. Live launch requires fresh
local Core evidence and enabled admission; Core performs final admission.

The request identity is generated when the form opens and retained through a
pending or unknown result. Repeated clicks cannot create a replacement identity.
The V5 command adapter reuses the established session/Cookie/Origin machinery;
it never reads worker credentials. A lost response reconciles using GET against
the original identity. Launch acknowledgement checks the exact input, including
build, scenario, inference mode and budgets. A same-ID mismatched record remains
unknown. A temporary 404 is not permission to resend.

Cancellation has its own command channel and remains available while a launch is
pending; it cannot be delayed by decorative presentation. A lost cancellation
response requires a cancelled record, or a separately labeled already-terminal
outcome. A running record with a matching ID cannot acknowledge cancellation.
Unknown commands block endpoint changes and further launches. In Trainer review
and unsubmitted launch forms, cancellation of a hidden previously selected
mission is disabled; return to Missions to select its exact identity.

The default **Mission bridge** direction uses a prominent state/outcome panel and
keyboard-focusable round/role cards. The **Technical handoff ledger** toggle is
a retained alternate with separate round/role/status, question, dispatch/accounting
and recorded reply sections. Subdued field labels, headings and spacing make the
technical evidence readable. Runtime data is inserted as plain text, never parsed
as formatting instructions. Exact JSON remains available in either direction. Current operation state,
not animation or card styling, determines the outcome. Native wide/compact form,
bridge, ledger and pending previews are retained in
[action evidence](../evidence/world/joint-actions-20260928/README.md) for product
feedback; owner visual acceptance remains open.

An isolated HTTP test exercised session/Origin checks, typed budgets, delayed
create visibility, lost cancellation response, wrong-build reconciliation,
policy rejection and terminal cancellation races. Five intended POSTs occurred;
all uncertain effects were reconciled by GET without duplicate dispatch. Existing
V2/V4 command and Operations HTTP journeys passed. In-memory command identity is
retained across hide/show, but this slice does not claim a durable client command
journal across application restart. Core records remain the recovery source.


## Practice duty

**Work → Practice** exposes the bounded V6 developmental learning loop, with
explicit enable, stop, cycle cancellation and stopped-baseline changes. It is
separate from read-only Trainer review proposals. See the
[practice client contract and recovery journey](local-practice-view.md).

Run the tracked local HTTP checks with `mise exec -- python scripts/check_world_joint.py`
and `mise exec -- python scripts/check_world_learning.py`. `just check-world` includes
both after the established operator HTTP checks. They bind random loopback ports,
use synthetic cookies and records, and never call a model, cluster or real Core.
