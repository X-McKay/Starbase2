"""Family-specific verifier/publication routing, with no provider or VM effects."""

import asyncio
import base64
import copy
from unittest.mock import AsyncMock

import pytest
from starbase_runtime import sdlc_pilot as pilot
from starbase_runtime import sdlc_revision_publish as publisher
from starbase_runtime import sdlc_verification as verifier
from starbase_runtime.review import digest
from test_sdlc_families import contract, sources


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
def test_public_capture_rejects_changed_family_test(monkeypatch, family):
    test_path, source = verifier.public_artifact(family)
    monkeypatch.setattr(pilot, "capture", AsyncMock(return_value=sources(family)))
    provider = AsyncMock(
        return_value={
            "type": "file",
            "encoding": "base64",
            "size": len(source.encode()),
            "content": base64.b64encode(source.encode()).decode(),
        }
    )
    monkeypatch.setattr(verifier, "get_json", provider)
    monkeypatch.setattr(pilot, "client", AsyncMock)
    assert asyncio.run(verifier.capture("a" * 40, family)) == sources(family)
    assert provider.await_args is not None
    assert test_path in provider.await_args.args[1]
    provider.return_value["content"] = base64.b64encode(b"weaker tests").decode()
    with pytest.raises(ValueError, match="configuration changed"):
        asyncio.run(verifier.capture("a" * 40, family))


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
def test_public_vm_contains_only_selected_trusted_test(monkeypatch, family):
    execute = AsyncMock(return_value={"exit_code": 0})
    monkeypatch.setattr(verifier.sdlc_sandbox, "_execute", execute)
    asyncio.run(verifier.public_tests("fixture", sources(family), family))
    test_path, source = verifier.public_artifact(family)
    assert execute.await_args is not None
    program = execute.await_args.args[1]
    assert test_path in program and repr(source) in program
    assert "test_persistence_history.py" not in program


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
def test_family_repair_and_review_use_selected_source(monkeypatch, family):
    cap = contract(family)
    source_path = cap["editable_paths"][0]
    original, corrected = sources(family), sources(family, corrected=True)
    parent = {"input": {"opportunity": family}}
    child: dict = {
        "id": "fixture-child",
        "evidence": {
            "verified": {
                "outcome": "failed",
                "sources": original,
                "observations": {"exit_code": 0, "cases": []},
                "public": {"exit_code": 1},
            }
        },
    }

    async def records(*args, **kwargs):
        return parent, copy.deepcopy(child)

    async def event(_input, key, stage, data):
        child["evidence"][stage] = data | ({"verdict": "improved"} if stage == "testing" else {})
        return copy.deepcopy(child)

    model = AsyncMock(
        side_effect=[
            {"output": {"decision": "implement"}},
            {
                "output": {
                    "rationale": "Scoped fixture repair",
                    "edits": [
                        {
                            "line": 7,
                            "lines": (
                                ["if memory_key is not None:"]
                                if family == "memory-key"
                                else [
                                    "if level is not None:",
                                    "    logger.setLevel(level)",
                                    "return logger",
                                ]
                            ),
                        }
                    ],
                }
            },
            {"output": {"status": "accept", "rationale": "Independent fixture review"}},
        ]
    )
    vm = AsyncMock(return_value={"exit_code": 0, "cases": []})
    public = AsyncMock(return_value={"exit_code": 0})
    monkeypatch.setattr(verifier, "records", records)
    monkeypatch.setattr(verifier, "event", event)
    monkeypatch.setattr(pilot, "member", model)
    monkeypatch.setattr(verifier.sdlc_families, "run", vm)
    monkeypatch.setattr(verifier, "public_tests", public)
    result = asyncio.run(verifier.verification_repair({"round": 0}))
    assert result["candidate_files"] == corrected
    assert not result["validation_error"]
    assert vm.await_args is not None and public.await_args is not None
    assert vm.await_args.args[2] == family and public.await_args.args[2] == family
    implementation = model.await_args_list[1].args[1]
    assert implementation["capability"] == cap and implementation["edit_format"] == "line-blocks"
    assert implementation["source"] == pilot.numbered_symbol(original, cap)
    review = asyncio.run(verifier.verification_review({"round": 0}))
    assert review["accepted"]
    assert model.await_args is not None
    assert model.await_args.args[1]["after"] == corrected[source_path]


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
def test_candidate_scope_artifact_and_status_match_family(family):
    cap = contract(family)
    original, corrected = sources(family), sources(family, corrected=True)
    authorized = {
        "evidence": {
            "verified": {"sources": original},
            "testing": {"artifact_digest": digest(corrected)},
            "reviewing": {"status": "accept"},
        }
    }
    assert publisher._candidate(authorized, corrected, cap) == digest(corrected)
    assert publisher.context({"input": {"opportunity": family}}) == f"starbase/{family}-regression"
    other = next(path for path in original if path != cap["editable_paths"][0])
    with pytest.raises(ValueError, match="unrelated"):
        publisher._candidate(authorized, corrected | {other: "changed"}, cap)
    with pytest.raises(ValueError, match="tested artifact"):
        publisher._candidate(authorized, corrected | {cap["editable_paths"][0]: "untested"}, cap)


def test_legacy_status_context_unchanged():
    assert publisher.context({"input": {}}) == "starbase/persistence-regression"


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
def test_family_status_and_corrected_git_tree(monkeypatch, family):
    import json

    import httpx
    from test_sdlc_revision_publish import Provider, mission

    cap = contract(family)

    class FamilyProvider(Provider):
        def http(self, request):
            if request.method == "POST" and request.url.path.endswith("/git/trees"):
                body = json.loads(request.content)
                assert [item["path"] for item in body["tree"]] == cap["editable_paths"]
                self.posts.append((request.method, "/git/trees", body, self.auths))
                return httpx.Response(201, json={"sha": "c" * 40})
            return super().http(request)

    provider = FamilyProvider(monkeypatch)
    provider.verification["evidence"]["verified"]["sources"] = sources(family)
    candidate = sources(family, corrected=True)
    provider.verification["evidence"]["testing"]["artifact_digest"] = digest(candidate)
    parent = mission()
    parent["input"]["opportunity"] = family
    receipt = asyncio.run(publisher.status(parent, provider.verification, False))
    assert receipt["context"] == f"starbase/{family}-regression"
    receipt = asyncio.run(publisher.update(parent, provider.verification, candidate))
    assert receipt["artifact_digest"] == digest(candidate)
    assert len([entry for entry in provider.posts if entry[1] == "/git/trees"]) == 1
