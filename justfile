set export
export PYTHONPATH := justfile_directory() / "services/runtime"
export UV_CACHE_DIR := justfile_directory() / ".local/cache/uv"

default:
    @just --list

bootstrap:
    python3 scripts/bootstrap.py

doctor:
    python3 scripts/doctor.py

build:
    cargo build --locked

dev: build
    python3 scripts/dev.py

demo id="first-survey":
    .venv/bin/python -m starbase_runtime.worker demo --id {{id}}

world:
    godot --path apps/world

# Builds and runs the packaged macOS game from outside the checkout.
check-world-export *args:
    python3 scripts/check_world_export.py {{args}}

world-crew:
    godot --path apps/world --script crew_gallery.gd

# Isolated art review; no backend or agent dispatch.
world-kit:
    godot --path apps/world res://scenes/kit/showroom.tscn

contracts:
    .venv/bin/python scripts/contracts.py

fmt:
    cargo fmt --all
    .venv/bin/ruff format services/runtime scripts
    .venv/bin/ruff check --fix services/runtime scripts

lint:
    cargo fmt --all --check
    cargo clippy --locked --all-targets -- -D warnings
    .venv/bin/ruff format --check services/runtime scripts
    .venv/bin/ruff check services/runtime scripts
    .venv/bin/ty check services/runtime scripts

test:
    cargo test --locked
    .venv/bin/python -m pytest -q

check: lint test
    cargo build --locked
    .venv/bin/python scripts/contracts.py --check
    python3 scripts/check_docs.py

check-world:
    python3 scripts/check_world.py
    .venv/bin/python scripts/check_world_commands.py

world-map:
    godot --path apps/world -- --colony-overview

world-shot:
    mkdir -p .local
    godot --path apps/world --max-fps 60 -- --capture="{{justfile_directory()}}/.local/world-preview.png" --frames=180

test-integration:
    cargo build --locked
    .venv/bin/python scripts/integration.py

eval-smoke:
    .venv/bin/python -m pytest -q
    cargo test --locked grading

# No provider calls; local services and sanitized inputs only.
test-operations:
    cargo build --locked
    .venv/bin/python scripts/operations_integration.py

# Explicit opt-in: twelve bounded calls to the configured development endpoints.
inference-pilot:
    .venv/bin/python scripts/inference_pilot.py

sandbox-doctor:
    .venv/bin/python scripts/sandbox_setup.py

sandbox-prepare:
    .venv/bin/python scripts/sandbox_setup.py --pull

# Real VM boundary probes; no model calls.
test-sandbox:
    .venv/bin/python scripts/sandbox_qualification.py
    .venv/bin/python scripts/sandbox_crash_probe.py

# Real Temporal, VM recovery, cancellation, and deterministic controls.
test-repairs:
    cargo build --locked
    .venv/bin/python scripts/repair_integration.py

# Explicit opt-in: three bounded calls to the configured development model.
repair-pilot:
    cargo build --locked
    .venv/bin/python scripts/repair_integration.py --inference

# Deployment preparation; mutations require explicit CLI flags, never implied by rendering.
deploy *args:
    .venv/bin/python scripts/deploy.py {{args}}

deployment-build *args:
    .venv/bin/python -m scripts.deployment.build {{args}}

check-deployment:
    .venv/bin/python -m pytest -q services/runtime/tests/test_deployment.py

# Disposable localhost PostgreSQL only. No Kubani credentials or volumes.
deployment-test-db:
    .venv/bin/python -m scripts.deployment.local_db start

test-postgres:
    STARBASE_TEST_POSTGRES=55439 cargo test --locked

deployment-rehearse: build
    .venv/bin/python -m scripts.deployment.rehearse

deployment-test-db-stop:
    .venv/bin/python -m scripts.deployment.local_db stop

# Preview one building definition; use count=50 for the shared-art load fixture.
world-building definition="repair" count="1":
    godot --path apps/world --script building_gallery.gd -- --definition=res://buildings/definitions/{{definition}}.tres --count={{count}}

# Real local Temporal and FalkorDB, synthetic provider inputs, recovery and replay.
test-field: build
    .venv/bin/python scripts/field_integration.py

# One optional advisory call to the configured development model.
field-pilot: build
    .venv/bin/python scripts/field_integration.py --inference

test-memory:
    .venv/bin/python scripts/memory_check.py

# Persistent development FalkorDB bound to loopback; Ctrl-C stops it cleanly.
memory-dev:
    .venv/bin/python scripts/memory_dev.py

# Actual Temporal/Core/FalkorDB, synthetic GitHub HTTP, repository-watch lifecycle.
test-repositories: build
    .venv/bin/python scripts/field_integration.py --repositories

world-command:
    godot --path apps/world -- --room=review --board

# Current illustrated crew and animation review; no backend activity.
world-characters:
    godot --path apps/world res://characters/showroom.tscn -- --production

# The illustrated captain is now enabled in the regular colony.
world-character-pilot:
    godot --path apps/world

check-characters:
    python3 scripts/check_characters.py

# Supply --blender /path/to/Blender on other hosts; requires version 4.5.3.
characters-render *args:
    python3 scripts/check_characters.py --render {{args}}

# Pack authored PNG frames from any editor; uses per-character source.json.
characters-pack frames_dir=".local/character-frames":
    godot --headless --path apps/world --script characters/pack.gd -- --frames-dir="{{justfile_directory()}}/{{frames_dir}}"
    python3 scripts/check_characters.py

# Rebuild illustrated PNGs and SpriteFrames from authored manifest/anchors.
characters-import *args:
    python3 scripts/check_characters.py --illustrated {{args}}

# Archived rejected 3D visual experiment; explicit opt-in only.
world-rig-study:
    godot --path apps/world res://characters/showroom.tscn
