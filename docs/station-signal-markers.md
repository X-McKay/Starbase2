# Exterior station record markers

Status: proposed

Implemented and checked in native local fixtures; owner visual acceptance open.

The exterior Command, Workshop and Trial Hall signs now distinguish the records
an operator can inspect. Previously a failed run and a completed run both produced
the same distant sign, and the near sign reported only a retained-result count.
The large-text setting also increased the font texture while cancelling that
increase in its screen-space scale. The focused regression reproduced all three
gaps before the rendering and projection change.

## Reading the sign

The sign retains one visible station at a time, entrance clearance, and the
existing nearest/selected-station rules. Text, static bracketed symbols and
restrained accent colors distinguish the following states without animation:

| Marker | Meaning and authoritative source |
|---|---|
| `[?] UNKNOWN` | No observed snapshot timestamp |
| `[/] OFFLINE` | Disconnected; counts describe the last known snapshot |
| `[~] STALE` | One or more projected records are stale |
| `[?] INCOMPLETE RECORDS` | Unknown record state or completion missing evidence |
| `[!] FAILED RESULTS` | Retained failed state or recorded repair execution error |
| `[#] BLOCKED RESULTS` | Retained terminal evidence explicitly says blocked |
| `[>] OPEN WORK` | At least one supported open run state |
| `[x] CANCELLED RESULTS` | Retained cancellation |
| `[=] NO CHANGE RECORDED` | Terminal evidence explicitly records no change |
| `[-] RETAINED RECORDS` | Other terminal records; completion is not verification |
| `[-] NO RETAINED RECORDS` | An observed snapshot contains no records for the station |

Freshness and incomplete records take priority over retained outcomes. Nearby
signs retain open and terminal counts alongside each nonzero failure, blocked,
cancelled, no-change, unknown and missing-evidence count. An old failed result
therefore never relabels the current open run as failed. Duplicate context-plus-ID
records retain only their newest revision. Fixture labels remain explicit.

## Interaction and accessibility

Clicking the sign or pressing **I** still opens native Station records, where
timestamps, individual identities and evidence remain available. Signs do not
dispatch work. The structured station selector is the equivalent route when a
sign is out of view or spatial rendering is unavailable.

The pointer target now follows the projected label bounds, including every line
of large mixed-result text. Horizontal edge clearance accounts for the complete
label width; solid scene occluders still block clicks through hidden signs.

Normal near text targets 17 screen pixels; large text targets 21. Distant text
targets 13 and 16 respectively. These are orthographic label sizing inputs, not
claims about DPI-independent physical dimensions or screen-reader qualification.
The signals have no animation, pulse or sound, so reduced motion retains the
same information. Existing crew animation and scene movement remain separate.

## Validation and remaining qualification

Focused station signal, station record and HUD polish checks pass. The initial
behavioral failures and a corrected test parse error are retained under
`.local/station-signals-20260927/`. The final native fixture run passed twenty
captures at 1280×800 and 800×640 on Godot 4.7.2 GL Compatibility / Apple M5.
Inspection confirmed readable static symbols and text for mixed outcomes,
blocked, unknown, stale and offline, compact large text, and the native record
inspector. Clicking the last line and pressing **I** both reach Station records;
reduced motion retains the same marker content. These are staged fixture states,
not production observations or a new physical-travel qualification.

Selected images, logs and slice source hashes are in the
[local evidence record](../evidence/world/station-signals-20260927/README.md).
The integrated `just check-world` run passed after both visual changes froze: 87
Godot import/scene stages plus command and operations HTTP fixtures. See the
[integration record](../evidence/playbooks-alignment-20260927/world-integration.md). No standalone export or screen-reader qualification was run for
this slice, and no performance improvement is claimed.

No API, authority, persistent state, imported asset or deployment changes are
introduced. Reverting the station signal implementation restores the old visual
projection without migrating data. Owner visual acceptance remains open.
