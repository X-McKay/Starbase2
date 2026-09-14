# September 2026 world and cast refactor

Status: accepted

Implementation is local on `codex/morning-at-starbase2`; deployment and real
production acceptance remain separate gates.

This change is the current handoff point for the Godot world, native operator
client and character production work. It is intentionally separate from the
browser delivery backlog and from real production acceptance.

## Current runtime

Godot is the product surface for the inhabited world, crew selection,
observability and operator actions. The current independent cast is:

| Stable ID | Display name | Role |
|---|---|---|
| `wayfinder` | Sho Junko | Operator |
| `rivet` | Rivet | Mender |
| `moss-cartographer` | Moss Bombadil | Surveyor |
| `stillpoint` | Mae Jin | Trainer |
| `night-shift` | Wes Walker | Watchkeeper |
| `prism` | Prism | Reviewer |
| `cybercat` | Cybercat | Alternate player |

The six crew models are independent Meshy outputs with model-owned materials,
rigs and social/work clips. Cybercat is a separate alternate player model,
rebuilt from the approved teal feline-suit reference. Its hair is rooted below
the helmet rim and uses bounded nape motion; helmet and armor remain rigid.
Reduced motion resets all secondary motion to the authored rest pose.

Legacy Vanguard, Sentinel, engineering-specialist, morning-work and shift-social
runtime trees were removed from the active checkout. A reversible local quarantine
copy is retained outside the repository while the refactor is reviewed. Historical
provenance records may still mention those names; they are not active runtime
inputs.

## Validation completed

The focused identity, Meshy import, social animation, Cybercat, cast continuity,
inhabited journey and native export checks pass. Repository checks pass for Rust,
Python, service pages, contracts and documentation. The world check was run with
native Godot permissions because the editor may emit local certificate and
settings diagnostics that are not product failures.

The commit deliberately excludes generated `evidence/` captures. Existing
historical evidence remains available in the repository, and new local captures
remain uncommitted until they are selected for a review record. Evidence is
review material, not a runtime dependency.

## Production source boundaries

`apps/world/assets/` contains the imported resources required to run Godot.
`assets-production/` contains selected Meshy inputs, Blender source projects,
export recipes and provenance. The old outfit preparation scripts still contain
historical source paths and must be archived or removed before anyone uses that
pipeline again; they are not part of the active runtime or `just` entry points.

## Remaining gates

Real-provider duty execution, live pause and reconnect journeys, persistent
memory, and the Godot Web export remain separate acceptance gates. The browser
plan in [Godot browser delivery](godot-web.md) is still proposed; the native
client is the supported operator experience today.
