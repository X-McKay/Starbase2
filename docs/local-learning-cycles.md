# Local developmental learning cycles

Status: accepted

Owner: Core/runtime and evaluation; world owns the Practice interaction. This
implements [ADR 0010](adr/0010-local-developmental-learning.md) and part of the
[autonomous RPG delivery contract](autonomous-rpg-delivery.md). It is local public
practice, not operational qualification or Kubernetes/Flux deployment.

## The complete bounded loop

An enabled duty runs without an open game client. Core selects retained V5
failure evidence, deduplicates it within the duty generation and reserves the
whole cycle budget. The Trainer proposes one typed Run book Procedure. Core
creates an immutable candidate differing from the incumbent only in that
Procedure, then admits eight trials in a fixed counterbalanced order: incumbent
and candidate on each of four public readiness cases. Temporal carries the
workflow; Core reads the retained results and independently decides the outcome.

A candidate may become the **practice incumbent** only when all four candidate
trials pass, the baseline passes fewer, no pair regresses, no hard or unknown gate
fails, and the incumbent generation still matches. Equal pass counts are
inconclusive. This deterministic public practice decision grants zero XP and no
operational skill qualification, production authority or statistical superiority.
Fresh held-out campaigns remain required for a claim of reusable improvement.

The default duty is disabled, allows at most two cycles per generation and has a
minimum sixty-second cooldown. Each cycle reserves one Trainer request with
32,768 tokens and eight mission grants of 24 requests / 384,000 tokens each:
193 requests and 3,104,768 tokens in total. These are ceilings, not claims about
actual consumption. Actual usage and unknown usage remain separately visible.
Changing the generation explicitly re-arms the bounded duty; a continuously
running worker cannot silently replenish its own allowance.

## Interaction and recovery

The Operations panel retains both Mission bridge and Technical ledger views.
The separate Practice tab exposes duty enable/stop, cycle cancellation, proposal,
paired results and the actual recorded adoption decision. An accepted request is
not a success outcome. Lost replies remain uncertain until an exact retained
record reconciles them; the client does not blindly repeat a command.

Core fences every proposal/trial dispatch by active duty, generation, deadline,
policy, immutable build and budget. The worker reconciles a stopped Core cycle and its admitted children even if
Temporal never created either workflow. Repeating cancellation repairs an
interrupted child-cancellation cascade. The one-shot proposal claim prevents a
provider call from being repeated after a crash. A saved response resumes; an
unresolved claimed call is accounted as unknown. Cancellation prevents future
dispatch and preserves already-started effects and late responses. Neither the
Trainer nor a crew member can replace the grader or adopt its own output.

Trainer context contains bounded excerpts of up to three retained source
missions and explicit coverage. Raw traces, credentials and grader implementation
are excluded. The candidate's experimental guidance is separate from its fixed
role/schema/authority instructions. Both byte bounds and structured-output
validation apply before the result is retained.

A stopped duty can explicitly change to a registered replacement baseline after
an agent-code upgrade. All cycles and started claims must be reconciled first.
Core retains an old/new-build receipt and prior cycles, increments the pointer
revision, and keeps the duty stopped. Enabling the new baseline is a separate
next-generation action; no evidence or qualification transfers to the new build.

## Running locally

Core and runtime use `STARBASE_JOINT_ENABLED=true` and
`STARBASE_LEARNING_ENABLED=true`, an existing narrow worker token, and the same
local Core/Temporal configuration as V5. The game then enables a bounded duty
from the Practice tab. Use the duty stop/cancel controls and leave the worker
running until started calls are reconciled before shutting it down. Feature
flags are installation configuration; they are not a substitute for finishing
in-flight accounting. Production deployment remains deferred.

## Reproduction and evidence

`just test-learning` starts fresh isolated Core and Temporal instances, seeds an
explicitly authored failed diagnostic, kills the worker after the proposal is
retained but before acknowledgement, restarts Core and worker, executes the
paired campaign and replays all histories. Authored controls prove wiring, not
model learning. Evidence and failed attempts stay under `.local/learning-*`.

`just learning-pilot` is an explicit local Qwen experiment. It imports retained
historical public failures with their original build identities as discovery
signals, freezes the current baseline, proposes once and retains every new
trial. It does not call Kubernetes, Flux, GitHub or a production effector. A failed
proposal or invalid trial remains part of the outcome; the harness does not keep
sampling until an improvement appears.

The new paired builds allow up to 8,192 output tokens per call, replacing the
2,048-token ceiling implicated in an earlier truncated public trial. Both arms
share this setting, and preflight reserves it inside the existing child grant.
Earlier-build scores are discovery evidence, not a matched baseline comparison.

The harness freezes candidate source files, grader/harness sources, executable
hash, initial declaration, exact cycle, per-trial records and Temporal histories.
Local token files and databases are not review artifacts. The model endpoint and
weight identity limitations, provider contention and actual measured costs must
be reported with any real inference result.

The initial scripted restart control completed all eight trials and replayed
all nine workflows. Later controls additionally passed claimed-proposal
cancellation and installation-disabled cleanup with a queued child and no
workflow. Both arms passed four of four and Core recorded
`inconclusive`, leaving the practice incumbent unchanged. Later source changes
require fresh validation; these controls do not certify model quality.

## Remaining delivery boundaries

This is a single-readiness-family local developmental loop. Priority scheduling,
capacity arbitration, held-out qualification, skill-tree admission, multi-domain
transfer, learned superiority and the live Kubani GitOps journey remain tracked
in the delivery contract. Production-quality art acceptance is separately
recorded in the [motion review](crew-work-motion-options.md); the current new
Equipment choreography is a Rivet slice, not a completed cast-wide action set.

## First real cycle and next completion conditions

The [retained Qwen cycle](../evidence/local-cycles-20260927/README.md) completed
all eight trials in 144.866 seconds: baseline 0/4, candidate 2/4, 33 requests and
39,668 reported tokens including the Trainer. Core recorded inconclusive and
retained the incumbent. Three failed lead outputs omitted required observation
and revision receipts. These valid protocol failures are not discarded or
retroactively repaired.

Runtime/evaluation owns the next reliability slice: expose bounded typed
validation diagnostics to the Trainer, make action-specific receipt requirements
clear in the provider-facing schema, and run a newly declared exact-build
campaign. Completion requires a candidate to meet all public practice gates,
then a separate held-out protocol for any qualification claim; budget growth or
one better rationale is insufficient. No new inference campaign is silently
started to replace this retained result.

World/Core owns spatial integration: persist explicit V5/V6 role-to-crew
assignments before driving new work/handoff animation from those records. Current
structured mission and Practice views are usable, while the living crew animation
continues to project its existing authoritative assignment records. Do not infer
permanent Classes or claim a visible crew member performed a V5 role solely from
a similar role name. Completion is an actual cycle with inspectable assignments,
arrival-gated work, cancellation/stale transitions and matching keyboard records.
