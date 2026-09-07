# Art source index

Use the [content convention](../docs/content-organization.md) for new families
and retention decisions. These are editable production sources; runtime files
live under `apps/world/`. Paid originals and ledgers remain in ignored
`meshy_output/` and are still needed by current build scripts.

| Family | Role | Entry point |
|---|---|---|
| `cybercat-vanguard` | Current player model | [Source and review](cybercat-vanguard/README.md); `just world-vanguard-build` |
| `engineering-polish` | Engineering shell, reactor, furnished interior and Mender | [Review](engineering-polish/REVIEW.md); `just world-engineering-build` |
| `meshy-blender` | Five-building authored colony and earlier Cybercat crew | [Pipeline](../docs/meshy-blender.md); `just world-colony-build` |
| `characters` | Illustrated crew and earlier character experiments | [Character contract](../docs/character-production.md) |

Existing family paths remain stable. A `.blend1` file is a recovery candidate,
not an additional selected source. See the [inventory assessment](../evidence/content-organization/README.md)
before cleanup; no source files were removed in that assessment.
