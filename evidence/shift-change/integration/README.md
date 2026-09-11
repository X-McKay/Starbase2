# Integrated checks

Status: proposed

The integrated runner was executed in order on the changed world. Earlier passing
checks were retained while actual failures were corrected and the remainder of
the suite was completed; green checks were not repeatedly rerun.

- `world-initial.log`: import and checks through character cadence passed. The
  Engineering test failed because its old ten-second allowance assumed a nearby
  workstation spawn. Its new bounded 120 seconds of deterministic physics
  includes the Habitat commute; arrival, stopped motion and authoritative console
  behavior remain required. `engineering-corrected.log` passes.
- `world-tail-02.log`: remaining structures, seamless travel, character showroom,
  field crew and kit checks passed. The structure catalog detected the old
  Habitat Crew marker inside the relocated sofa. The marker moved into the
  clear aisle; geometry and navigation clearance did not change.
  `structures-corrected.log` passes every catalog anchor and route.
- `world-tail-03.log`: an old room-switch assertion assumed the Surveyor always
  stayed north of z=20. Its Commons home is legitimately south of that line.
  The corrected test requires its actual position to remain within 0.1m during
  room switching, explicitly rejecting a camera-induced teleport.
- Final room/interaction results are retained in `world-tail-04.log`.

The isolated HTTP command and operations suites passed separately under
`../ui/`. Their local fixture writes used no providers or production credentials.
The social, real physical home routes, watch controls and large-text layout
checks ran within the initial integrated invocation. Final native export
qualification has its own exact-artifact manifest.

Two preliminary package qualifications were intentionally stopped at their exact
owned headless smoke process after integrated failures surfaced. Their fresh
output directories and logs remain under `.local/reviews/shift-change/` as
`20260910-final-01` and `20260910-final-02`; neither is a qualified artifact.

The third package attempt passed its exported headless journeys and native
colony capture, then the compact interior screenshot failed to complete while
backgrounded. Its exact process was sampled and stopped; retain
`native-interior-stall.sample.txt` and the `20260910-final-03` logs. The legacy
explicit screenshot paths in `world.gd`, `package_capture.gd` and `live_capture.gd`
now request `RenderingServer.force_draw(false)` before reading the real viewport,
matching the already successful social/domestic capture path. They no longer
await a potentially absent background `frame_post_draw`. This affects explicit
review capture only. All three scripts parse and the isolated-input regression
passes; the fresh final artifact validates actual native outputs.

The fourth export rendered the compact interior and all room views, confirming
explicit drawing. Its structure review then reported two obsolete assumptions:
E in Habitat can now legitimately select a nearby crew member, and Surveyor
need not be beside the Command console when a fixture assignment arrives.
The capture opens the same room-guide action directly and uses explicit Watch
to follow the actual assigned crew. It also advances synthetic observation/run
timestamps coherently, so fixture activity is not stale by construction.
`20260910-final-04/structure-captures.json` retains both initial failures. The
fresh fifth export qualifies these capture changes; no crew teleport or forced
operational timing was introduced.
