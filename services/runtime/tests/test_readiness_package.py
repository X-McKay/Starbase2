"""The packaged agent must assemble exactly the declared capability."""

import asyncio
import json
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest
from pydantic import ValidationError
from starbase_runtime.agents.readiness.definition import AgentDefinition, load_definition
from starbase_runtime.readiness import MissionSession, build_manifest, make_agent, scripted_model


def test_definition_rejects_unknown_tools_authority_and_invalid_budgets():
    original = load_definition().model_dump()
    for field, value in (
        ("tools", ["shell"]),
        ("authority", "production"),
        ("retries", -1),
        ("extra", "ignored"),
    ):
        with pytest.raises(ValidationError):
            AgentDefinition.model_validate(original | {field: value})
    for value in (0, -1, True, float("inf")):
        mutated = json.loads(json.dumps(original))
        mutated["policy"]["total_tokens"] = value
        with pytest.raises(ValidationError):
            AgentDefinition.model_validate(mutated)


def test_packaged_resources_load_outside_checkout(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    definition = load_definition()
    assert definition.name == "readiness_crew_v1"
    assert definition.policy.total_tokens == 128000
    from starbase_runtime.readiness import instructions

    assert "Run book Procedure" in instructions("runbook-v1")


def test_build_covers_nested_code_resources_and_declared_configuration():
    build = build_manifest({"mode": "scripted", "name": "test", "endpoint": None})
    sources = build["manifest"]["sources"]
    assert any(p.endswith("agents/readiness/agent.json") for p in sources)
    assert any(p.endswith("agents/readiness/factory.py") for p in sources)
    assert any(p.endswith("agents/readiness/models.py") for p in sources)
    assert build["manifest"]["agent_definition"] == load_definition().model_dump(mode="json")


def test_factory_uses_declared_settings_and_preserves_decision_boundary(tmp_path):
    from pydantic_ai.models.function import FunctionModel

    from services.runtime.tests.test_readiness_mission import Port

    declared = load_definition()
    scripted = scripted_model()
    assert scripted.function is not None
    scripted_response = scripted.function
    observed = []

    def respond(messages, info):
        observed.append(info.model_settings)
        return scripted_response(messages, info)

    async def run():
        port = Port()
        session = MissionSession(port, tmp_path / "mission.json", {"digest": "control"})
        result = await make_agent(FunctionModel(respond)).run("Inspect", deps=session)
        assert port.applies == 0
        await session.finish(result.output)
        assert session.record["state"] == "verified-repair"

    asyncio.run(run())
    assert observed[0] == declared.model_settings.model_dump(mode="json")


def test_package_loads_from_isolated_archive(tmp_path):
    """Exercise resource loading without the checkout on the child import path."""
    import starbase_runtime

    assert starbase_runtime.__file__ is not None
    root = Path(starbase_runtime.__file__).parent
    archive = tmp_path / "runtime.zip"
    with zipfile.ZipFile(archive, "w") as bundle:
        bundle.write(root / "__init__.py", "starbase_runtime/__init__.py")
        for path in (root / "agents").rglob("*"):
            if path.is_file() and path.suffix in {".py", ".json", ".md"}:
                bundle.write(path, str(Path("starbase_runtime") / path.relative_to(root)))
    code = """
import sys
sys.path.insert(0, sys.argv[1])
from starbase_runtime.agents.readiness.definition import instructions, load_definition
from starbase_runtime.agents.readiness.factory import make_agent
assert load_definition().policy.total_tokens == 128000
assert 'Run book Procedure:' in instructions('runbook-v1')
assert callable(make_agent)
"""
    subprocess.run(
        [sys.executable, "-I", "-c", code, str(archive)],
        cwd=tmp_path,
        check=True,
        capture_output=True,
        text=True,
    )


def test_changed_package_resources_require_new_build(tmp_path, monkeypatch):
    from starbase_runtime.agents.readiness import definition

    (tmp_path / "agent.json").write_bytes(definition.resource_bytes("agent.json") + b"\n")
    monkeypatch.setattr(definition, "files", lambda package: tmp_path)
    with pytest.raises(ValueError, match="new immutable build"):
        definition.load_definition()
