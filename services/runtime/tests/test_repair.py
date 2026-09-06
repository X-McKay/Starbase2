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
