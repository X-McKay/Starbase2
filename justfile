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

world *args:
    python3 scripts/world.py {{args}}

# Builds and runs the packaged macOS game from outside the checkout.
check-world-export *args:
    python3 scripts/check_world_export.py {{args}}

# Downloads only the checksum-pinned Godot Web templates into .local/.
world-web-templates *args:
    python3 scripts/install_godot_web_templates.py {{args}}

# Export-only toolchain probe; it does not change the main world's Web preset.
check-world-web-probe *args:
    python3 scripts/check_world_web_probe.py {{args}}

# Runs two clean staged exports; it does not edit the checked-out world project.
check-world-web *args:
    python3 scripts/check_world_web.py {{args}}

prepare-world-web-transport *args:
    python3 scripts/prepare_world_web_transport.py {{args}}

web-fixture *args:
    cargo build --locked -p starbase-core --example web_fixture
    target/debug/examples/web_fixture {{args}}

check-web-fixture *args:
    cargo build --locked -p starbase-core --example web_fixture
    python3 scripts/check_web_fixture.py {{args}}

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
    .venv/bin/python -m pytest -q scripts/test_world_web_tools.py

check: lint test
    cargo build --locked
    .venv/bin/python scripts/check_service_page.py
    .venv/bin/python scripts/contracts.py --check
    python3 scripts/check_docs.py

check-world:
    python3 scripts/check_world.py
    .venv/bin/python scripts/check_world_commands.py
    .venv/bin/python scripts/check_world_operations.py

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

# Exact local Linux images in a disposable pod; output must be a new directory.
deployment-qualify-images inputs output:
    .venv/bin/python -m scripts.deployment.image_rehearsal {{inputs}} {{output}}

deployment-test-db-stop:
    .venv/bin/python -m scripts.deployment.local_db stop

# Preview one building definition; use count=50 for the shared-art load fixture.
world-structure definition="repair" count="1":
    godot --path apps/world --script structure_gallery.gd -- --definition=res://structures/definitions/{{definition}}.tres --count={{count}}

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

# Detailed Meshy character; isolated visual inspection with keyboard controls.
world-meshy-character:
    godot --path apps/world --script characters/meshy_preview.gd

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

# Rebuild authored native buildings; no Meshy API calls or credit spend.
world-colony-build blender="/Applications/Blender.app/Contents/MacOS/Blender":
    "{{blender}}" --background --factory-startup --python assets-production/scripts/build_colony.py
    python3 assets-production/scripts/connect_colony.py
    python3 assets-production/scripts/connect_engineering.py
    godot --headless --path apps/world --editor --import --quit

# Rebuild selected remaining structures from retained local inputs; no paid calls.
world-remaining-build blender="/Applications/Blender.app/Contents/MacOS/Blender":
    "{{blender}}" --background --factory-startup --python assets-production/scripts/build_remaining_structures.py
    "{{blender}}" --background --factory-startup --python assets-production/scripts/prepare_remaining_props.py
    for asset in command training habitat botanical; do "{{blender}}" --background --factory-startup --python assets-production/scripts/prepare_remaining_hulls.py -- --asset "$asset"; done
    python3 assets-production/scripts/connect_remaining_structures.py
    godot --headless --path apps/world --editor --import --quit

# Rebuild authored living-colony additions around retained Meshy assets; no paid calls.
world-living-build blender="/Applications/Blender.app/Contents/MacOS/Blender":
    "{{blender}}" --background --factory-startup --python assets-production/scripts/build_remaining_structures.py
    "{{blender}}" --background --factory-startup --python assets-production/scripts/build_living_commons.py
    python3 assets-production/scripts/connect_remaining_structures.py
    godot --headless --path apps/world --editor --import --quit

# Review continuous Engineering entry and the rest of the colony.
world-seamless:
    godot --path apps/world -- --room=repair

# Rebuild the approved Engineering slice from retained Meshy downloads; no paid calls.
world-engineering-build blender="/Applications/Blender.app/Contents/MacOS/Blender":
    "{{blender}}" --background --factory-startup --python assets-production/scripts/build_engineering.py
    "{{blender}}" --background --factory-startup --python assets-production/scripts/prepare_models.py
    python3 assets-production/scripts/connect_engineering.py
    godot --headless --path apps/world --editor --import

# Offline authoring/preparation only; selected Meshy originals must already exist.
world-inhabited-build blender="/Applications/Blender.app/Contents/MacOS/Blender":
    "{{blender}}" --background --factory-startup --python assets-production/scripts/prepare_inhabited_props.py
    "{{blender}}" --background --factory-startup --python assets-production/scripts/build_remaining_structures.py
    "{{blender}}" --background --factory-startup --python assets-production/scripts/build_colony_vent.py
    python3 assets-production/scripts/connect_remaining_structures.py
    godot --headless --path apps/world --editor --import --quit
