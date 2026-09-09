# Native launch observation

During `20260909-final-01`, the second (interior) exported native launch remained
on the Godot splash screen for about two minutes. stdout/stderr were empty at
inspection and the qualification timeout had not elapsed. CUA confirmed the
actual splash window. The task-owned app was brought to the foreground through
macOS activation; the interior PNG, metadata and clean log then completed within
the existing bound, and the runner advanced to the structure captures.

This is an observed sequence, not proof of a specific engine defect or its cause.
An attempted subsequent one-second process sample found the interior process
already exited and produced no sample. No source, capture file or pass threshold
was changed. The final manifest and captured pixels remain the qualification
record; activation alone was not counted as a pass.

The subsequent structures phase exceeded its existing 180-second bound before
operations captures were produced. The attempt is failed (`export-01.log`). A
one-second stack sample found the main thread mostly in frame-loop sleep, not
proof of a specific stall cause. Cleanup missed the process because Launch
Services reported `/private/var` while the runner matched `/var`; the exact owned
PID was then terminated.

The runner now waits for its exact process and explicitly activates that app at
launch, preserving the 180-second total bound. Cleanup matches the original and
resolved executable paths; a regression test rejects similarly named/unrelated
processes. A fresh output directory is required for the next qualification.

`export-02.log` failed before capture because JSON's default ASCII escaping emitted
`\u00b7` in the AppleScript application name. AppleScript rejected that expression.
The launcher now retains the literal Unicode name; both a mocked activation
regression and an actual AppleScript string parse passed. The app-error, timeout,
exact PID and alias tests remain intact. A fresh `20260909-final-03` is required;
no earlier screenshot is substituted for its outputs.

`export-03.log` also exceeded the structure bound despite manual reactivation.
Its colony metrics recorded 8,016 process intervals for a capture requested at
frame 600: the process loop continued while `frame_post_draw` was pending.
Reactivation completed individual pending draws, but intermittent manual actions
were insufficient for the whole journey. No frame-rate regression is established
by the waiting time; its recorded median process interval was 16.669 ms.

The runner now uses the canonical application path and reactivates only the exact
owned process every two seconds while awaiting completion. It starts no second
instance and retains the same total 180-second bound. PID, Unicode, pending-draw
reactivation, timeout and app-error tests pass; the full Python suite has 102
passing tests. This is a supervised visible-window qualification, not an
unattended/occluded rendering guarantee. `20260909-final-04` is the fresh candidate.

`export-04.log` completed the operations captures but failed the review physical
arrival and airlock closure checks. It is not qualified. The old capture report
did not record each walk's final route or input state, so the cause cannot be
established from that attempt. A source-native diagnostic run retained in
`diagnostic-native-05.log` passed all journeys, including a review exit distance
of 0.210 metres. This does not resolve the earlier exported failure. Future
capture reports now retain each walk's start, target, actual position, remaining
route, panel/input state and final collision information without changing the
arrival or airlock thresholds.

Actual screenshot review found insufficient compact form space, nested history
scrolling and an unreadable distant task-marker capture. The panel now provides
a collapsible briefing and side-by-side history/evidence; the marker capture
walks to the review console and uses the existing zoom controls. A fresh fifth
export checks these changes. Earlier PNGs remain failed-attempt evidence.

The fifth export passed, with 15 recorded walks and zero failures. Its review
exit measured 0.210 metres from the target, no remaining route or collision,
no open panel and no observed manual movement input. This establishes the
recorded candidate's result, not the cause or elimination of the earlier
intermittent failure. Keep that limitation attached to this local qualification.
