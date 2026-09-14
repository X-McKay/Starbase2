# Player character selection

Status: accepted

Settings → Character lets the user choose Sho Junko or Cybercat as the player avatar. The existing keyboard Settings shortcut (H), section navigation and focusable choice buttons provide the same path without pointer input. The selected name appears below the buttons. This is a local cosmetic preference; the player remains the operator and the five NPC roles retain their definitions and backend identities.

Selection replaces the player's visual definition on the existing CharacterBody3D. Position, route, collision capsule, motion, gait phase, facing and reduced-motion state are retained. The previous visual is detached before deletion so only one rendered model remains. The explicit `--character-pilot` review flag continues to select the operator pilot when Sho Junko is chosen; Cybercat uses its own production definition.

The choice is saved through ConfigFile to `user://starbase2-player.cfg`, section `player`, key `character`, with IDs `operator` and `cybercat`. Missing, malformed or unsupported preferences default to Sho Junko; an unavailable catalog resource also falls back to the operator. A failed save leaves the local choice active and displays a save failure beside the selected name. Other display/audio controls retain their existing persistence behavior.

Fixture worlds do not read or write personal preferences by default. Tests can inject a temporary path through `player_preferences_path`; the focused selection test uses a process-specific temporary file and removes it afterward. This prevents a saved live avatar from silently changing unrelated fixture expectations.

Verification lives in `apps/world/test_player_character.gd`: actual Settings switch/back, preserved movement state/body/collider, NPC identity and snapshot preservation, fresh-world restoration, invalid preference fallback and no dispatch. Optional `--capture-dir=<directory>` captures native full-width and compact large-text settings plus the selected Cybercat world view. Run with `--fixed-fps 60`; capture remains an explicit test mode. The parent task owns native visual review and asset qualification.
