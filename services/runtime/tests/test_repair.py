import asyncio
import json

import pytest
from pydantic import ValidationError
from starbase_runtime.repair import Patch, program
from starbase_runtime.sandbox import POLICY, remove, run


def test_candidate_cannot_include_tools_or_self_grades():
    with pytest.raises(ValidationError):
        Patch.model_validate({"source": "pass", "rationale": "fine", "success": True})
    with pytest.raises(ValidationError):
        Patch(source="x" * 16001, rationale="too large")


def test_wire_harness_contains_inputs_but_no_expected_answers():
    p = program("def transform(value): return value", [-12, 0, 100])
    assert "expected" not in p and "grade" not in p
    assert "[-12, 0, 100]" in p
    assert POLICY["network"] == "none" and POLICY["host_mounts"] == []


def test_sandbox_rejects_unowned_identity_and_excess_input_before_execution():
    with pytest.raises(ValueError, match="identity"):
        asyncio.run(remove("user-sandbox"))
    with pytest.raises(ValueError, match="budget"):
        asyncio.run(run("sb-test", "x" * 24001))


def test_qualification_probes_are_retained():
    from pathlib import Path

    evidence = Path("evidence/sandbox-qualification/probes.json")
    # Checked-in qualification is evidence, not silently rerun virtualization in unit tests.
    data = json.loads(evidence.read_text())
    assert set(data) == {"isolation", "memory", "disk", "timeout", "background", "cancellation"}
    assert all(v["passed"] for v in data.values())


def test_sandbox_image_is_pinned_per_architecture():
    import platform
    import re

    from starbase_runtime.sandbox import IMAGE, IMAGES, image_for

    # One immutable manifest digest per supported CPU architecture; an index digest
    # would let the runtime silently resolve a different image per host.
    assert set(IMAGES) == {"aarch64", "x86_64"}
    assert all(re.fullmatch(r"python@sha256:[0-9a-f]{64}", value) for value in IMAGES.values())
    assert len(set(IMAGES.values())) == 2
    assert image_for("arm64") == image_for("aarch64") == IMAGES["aarch64"]
    assert image_for("x86_64") == image_for("amd64") == IMAGES["x86_64"]
    with pytest.raises(RuntimeError, match="architecture"):
        image_for("riscv64")
    assert POLICY["image"] == IMAGE == image_for(platform.machine())
