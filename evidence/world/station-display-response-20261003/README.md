# Workstation display response · 2026-10-03

Native Godot 4.7.2 Compatibility captures from the local source checkout at
1440×900 on Apple M5. The isolated fixture uses synthetic contact weights and
dispatches no command. This is visual evidence, not packaged-build qualification
or owner art acceptance.

- `display-idle.png`: seated Command console with no active input cue.
- `display-key-contact.png`: the same frame with a display-local sweep while an
  actual seated key contact is projected.

The first placement attempt was offset from the display; its `attempt1-*` files
remain local for diagnosis. The correction anchors the cue to the large display
in room space while the chair tray moves independently. The focused standing
and seated tests verify idle, closed-tray, malformed, and contact-loss reset.
