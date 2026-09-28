"""Authored public fixture controls; no repository-supplied code executes on host."""

import json
import os
import subprocess
import sys

import pytest
from starbase_runtime import sdlc_capabilities, sdlc_families, sdlc_pilot, sdlc_sandbox

MEMORY = """class SimplePersistence:
    def __init__(self, path):
        self.memory = {}
    def save_agent_memory(self, agent, key, value):
        self.memory.setdefault(agent, {})[key] = value
    def get_agent_memory(self, agent, memory_key=None):
        if memory_key:
            return self.memory.get(agent, {}).get(memory_key)
        return dict(self.memory.get(agent, {}))
    def unrelated(self):
        return 42
"""
LOGGING = """import logging
def get_logger(name, level=None):
    logger = logging.getLogger(name)
    if not logger.handlers:
        logger.addHandler(logging.StreamHandler())
        logger.setLevel(level or "INFO")
    return logger

def unrelated():
    return 42
"""


def sources(family, corrected=False):
    files = dict.fromkeys(sdlc_sandbox.FILES, "")
    files["src/utils/persistence.py"] = MEMORY
    files["src/utils/logging.py"] = LOGGING
    if corrected and family == "memory-key":
        files["src/utils/persistence.py"] = MEMORY.replace(
            "if memory_key:", "if memory_key is not None:"
        )
    if corrected and family == "logging-level":
        files["src/utils/logging.py"] = LOGGING.replace(
            "    return logger",
            "    if level is not None:\n        logger.setLevel(level)\n    return logger",
        )
    return files


def contract(family):
    return sdlc_capabilities.contract_for("x-mckay/algent", family)


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
def test_detector_positive_and_corrected_nochange(family):
    assert sdlc_pilot.applicable(sources(family), contract(family))
    assert not sdlc_pilot.applicable(sources(family, corrected=True), contract(family))


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
@pytest.mark.parametrize("source", ["def broken(:", "def unrelated():\n    return 1\n"])
def test_detector_malformed_or_missing_symbol_is_unavailable(family, source):
    files = sources(family)
    files[contract(family)["editable_paths"][0]] = source
    with pytest.raises((ValueError, SyntaxError)):
        sdlc_pilot.applicable(files, contract(family))


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
def test_apply_accepts_only_selected_function(family):
    files = sources(family)
    capability = contract(family)
    path = capability["editable_paths"][0]
    patch = sdlc_pilot.Patch(
        rationale="public control",
        edits=[
            sdlc_pilot.Edit(path=path, old=files[path], new=sources(family, corrected=True)[path])
        ],
    )
    candidate = sdlc_pilot.apply(files, patch, capability)
    assert candidate == sources(family, corrected=True)
    assert files == sources(family)
    bad_patch = patch.model_copy(
        update={"edits": [sdlc_pilot.Edit(path=path, old="return 42", new="return 43")]}
    )
    with pytest.raises(ValueError, match="unrelated"):
        sdlc_pilot.apply(files, bad_patch, capability)
    other = "src/utils/logging.py" if family == "memory-key" else "src/utils/persistence.py"
    wrong_path = patch.model_copy(
        update={"edits": [sdlc_pilot.Edit(path=other, old="return 42", new="return 43")]}
    )
    with pytest.raises(ValueError, match="absent or ambiguous"):
        sdlc_pilot.apply(files, wrong_path, capability)


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
@pytest.mark.parametrize("corrected", [False, True])
def test_public_unittest_artifact_detects_fixture_regression(tmp_path, family, corrected):
    files = sources(family, corrected)
    test_path, test_source = sdlc_families.public_artifact(family)
    files[test_path] = test_source
    for name, source in files.items():
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
    environment = {
        key: value for key, value in os.environ.items() if key in {"PATH", "LANG", "TMPDIR"}
    }
    result = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tests"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert (result.returncode == 0) is corrected, result.stderr
    if not corrected:
        assert "AssertionError" in result.stderr


def observations(family):
    return [
        {"id": identity, "actual": [1]} for identity in contract(family)["verification"]["case_ids"]
    ]


@pytest.mark.parametrize("family", ["memory-key", "logging-level"])
def test_raw_observations_parse_without_claiming_correctness(family):
    cases = observations(family)
    text = sdlc_families.PREFIX + json.dumps({"cases": cases})
    assert sdlc_families.observations(text, family) == cases
    assert sdlc_families.observations("diagnostic\n" + text, family) == cases


@pytest.mark.parametrize(
    "payload",
    [
        {"cases": []},
        {"cases": None},
        {},
        {"cases": [{"id": "unknown", "actual": []}] * 6},
        {"cases": [{"id": "memory_empty_key", "actual": [True]}] * 6},
    ],
)
def test_missing_and_malformed_raw_cases_are_rejected(payload):
    with pytest.raises(ValueError):
        sdlc_families.observations(sdlc_families.PREFIX + json.dumps(payload), "memory-key")


@pytest.mark.parametrize("payload", ["", "garbage", "STARBASE_ALGENT_FAMILY_V1=not-json"])
def test_missing_or_invalid_envelope_is_rejected(payload):
    with pytest.raises(ValueError):
        sdlc_families.observations(payload, "memory-key")


def test_duplicate_and_out_of_order_observations_are_rejected():
    cases = observations("memory-key")
    text = sdlc_families.PREFIX + json.dumps({"cases": cases})
    with pytest.raises(ValueError):
        sdlc_families.observations(text + "\n" + text, "memory-key")
    with pytest.raises(ValueError):
        sdlc_families.observations(
            sdlc_families.PREFIX + json.dumps({"cases": cases[::-1]}), "memory-key"
        )


def test_family_program_preserves_shared_source_boundary():
    files = sources("memory-key") | {"credentials.txt": "forbidden"}
    with pytest.raises(ValueError):
        sdlc_families.program(files, "memory-key")


@pytest.mark.parametrize("payload", [None, [], 7, {"cases": [None] * 6}, {"cases": [1] * 6}])
def test_nonobject_envelopes_and_cases_are_explicitly_rejected(payload):
    with pytest.raises(ValueError):
        sdlc_families.observations(sdlc_families.PREFIX + json.dumps(payload), "memory-key")


@pytest.mark.parametrize("mutation", ["bool", "string", "too_long", "extra", "missing"])
def test_first_case_shape_fences_before_any_grading(mutation):
    cases = observations("memory-key")
    if mutation == "bool":
        cases[0]["actual"] = [True]
    elif mutation == "string":
        cases[0]["actual"] = ["7"]
    elif mutation == "too_long":
        cases[0]["actual"] = [1] * 101
    elif mutation == "extra":
        cases[0]["claimed_pass"] = True
    else:
        del cases[0]["actual"]
    with pytest.raises(ValueError):
        sdlc_families.observations(
            sdlc_families.PREFIX + json.dumps({"cases": cases}), "memory-key"
        )
