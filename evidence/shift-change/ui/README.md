# Shift Change controls

Status: proposed

Implemented on `codex/shift-change`. The Godot crew strip opens the existing
native inspector; watching a crew member is an explicit inspector action.
Watching changes camera/cutaway presentation without moving the operator,
changing the operator's room, changing records or dispatching work. Escape,
manual movement, path selection, visiting a room or opening the map returns
to the operator view. L visits Habitat. Expanded Command/Journal workspaces
hide the bottom world controls until closed.

`watch-passed.log` verifies the real room cutaway, visible crew, operator
position and record/command invariants. `controls-passed.log` verifies native
inspection, explicit watch selection, truthful state captions and large-text
bounds at 1280×800 and 800×640. The initial strip overflow remains in
`failed-strip-overflow.log`. The later visibility assertion incorrectly checked
a child's own `visible` flag while its parent was hidden; the corrected check
uses `is_visible_in_tree()` and the failed assertion is preserved separately.

`commands-passed.log` exercises local-origin enforcement, pending deduplication,
denial, lost-response reconciliation and no redispatch through isolated HTTP
fixtures. `operations-passed.log` exercises review/evaluation forms, duty
reconciliation, history and unknown-policy fencing. These fixture writes are
local test requests; they do not prove or alter production operations.

Final integrated results and native visual evidence are recorded separately.
Owner art and play-feel acceptance remains open.
