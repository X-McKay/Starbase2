# Handoff dialogue

Status: proposed · implemented 2026-10-04 in the native client (agent transparency, slice 4, page 3)

The handoff dialogue shows a review handoff as two speech cards between crew
members, above a stage track for the mission. It reads the same retained records
as the [workstation screen](workstation-screen.md) and never dispatches work.

## Opening it

| Way in | Result |
|---|---|
| **U** | Toggles the dialogue for the mission of the focused (or default) crew member. |
| Crew strip **Handoff [U]** | The same. |
| **← / →** or **← Review / Review →** | Step between recorded reviews, oldest to newest. It opens on the newest. |
| **PageUp / PageDown** | Scroll the cards when they stack (compact window with larger text). |
| **Console [N]** | Switch to the workstation screen. |
| **Esc** or **Close [Esc]** | Close. |

The dialogue keeps the masthead and navigation visible and sits beside and below
them.

## What it shows

**Heading:** who hands what to whom, from the review status. For example "Prism
returns the candidate to Rivet" with "reviewing → implementing · round 1 → 2", or
"Prism accepts Rivet's round 2". It also shows the freshness text, prefixed
`LAST KNOWN` when stale.

**Reviewer card:** the review's recorded `rationale` in quotes, its findings
(`path:line problem`), and missing evidence. The status reads `[!] changes
requested`, `[=] accepted`, `[?] abstained` or `[?] status not recorded`. A
patch-validator review shows Core as the speaker, `[x] not executed` and the
validation error. The footnote gives the record time and says the reasoning
behind the output is not recorded.

**Reply card:** the implementer's reply is the `rationale` recorded with the next
round's candidate (`testing-(N+1)` → `patch.output.rationale`). Nothing else is
used as a reply, and no reply text is ever written for the crew. The states are:

| State | Card |
|---|---|
| Next round recorded | `[=] round N+1 submitted` and the quoted rationale |
| Revising, stream live | `[>] revising · reply not recorded yet` |
| Revising, stream not live | `[?] last known · reply not recorded` |
| Mission blocked, failed or stopped | `[\|\|] no reply · mission blocked` (failed uses `[x]`) |
| Review accepted | `[-] no reply needed` |
| Otherwise | `[?] reply not recorded` |

If the implementer was reassigned (Core's fallback), the reply card names the crew
member recorded with the candidate. The footer lists any reassignment.

**Stage track:** plan → implement rN → test rN → review rN → ↺ round N → N+1 → …
→ ready to publish → Reality Gate · branch + PR → awaiting human review. Each chip
has a glyph and text: `[=]` done, `[>]` current, `[!]` changes, `[x]` failed,
`[||]` blocked, `[?]` unknown, `[ ]` not reached. A past round's test verdict comes
from the stream's `mission.stage` event when this client saw it; otherwise the chip
reads "verdict not retained", because Core keeps grading only for the current round.
The footer gives the mission objective, the revision loops used against the limit,
and the fallback implementer.

**No handoff yet:** a single card reads `[-] No review handoff recorded yet ·
Prism is reviewing round 1` (or the matching phrase). Without the full record it
reads `[?] … needs the full mission record`. The summary's review status and
finding count are shown when they are known.

## Verification and limitations

`apps/world/test_transparency_pages.gd` covers the heading, both cards, the
track statuses, pending, stale and blocked replies, missing records, no review
and no mission, and the dialogue layout at 1440×900 and 960×700 with normal and
larger text. The native captures are `handoff-dialogue.png` and
`handoff-dialogue-compact.png` in
[the evidence folder](../evidence/world/transparency-20261004/README.md).

The cards sit at fixed screen positions. They are not anchored to the actors, and
the world does not stage a physical meeting for the dialogue. The existing
recorded-handoff choreography (`crew_handoff.gd`) is unchanged. The other
limitations are the same as for the [workstation screen](workstation-screen.md#limitations).
