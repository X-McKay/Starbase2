"""Pinned repository contracts and task handoffs; catalogs never confer authority."""

import copy
import json

from .review import ROOT, digest

_CATALOG = json.loads((ROOT / "contracts/repository-capabilities.json").read_text())
for _contract in _CATALOG["capabilities"]:
    _contract["digest"] = digest(_contract)


def catalog() -> dict:
    return copy.deepcopy(_CATALOG)


def contract_for(repository: str, opportunity: str) -> dict:
    for contract in _CATALOG["capabilities"]:
        if contract["repository"] == repository.lower() and contract["opportunity"] == opportunity:
            return copy.deepcopy(contract)
    raise ValueError("No installed repository capability supports this opportunity")


def compatible_contract(snapshot: dict, local: dict) -> bool:
    """An older Core may finish old work, but cannot admit this contract-aware build."""
    return local in snapshot.get("capability_catalog", {}).get("capabilities", [])


def assignment(run: dict, role: str, local: dict) -> dict | None:
    if not run["input"].get("capability_digest"):
        return None  # Original V7 histories retain their original execution contract.
    if run.get("capability") != local or run["input"]["capability_digest"] != local["digest"]:
        raise ValueError("Pinned repository capability unavailable")
    expected = local["assignments"]
    actual = run.get("coordination", {}).get("assignments")
    if not isinstance(actual, list) or len(actual) != len(expected):
        raise ValueError("Crew assignments differ from the pinned contract")
    for selected, original in zip(actual, expected, strict=True):
        allowed = [original["crew"]] + original.get("fallback_crews", [])
        if selected.get("crew") not in allowed or selected | {"crew": original["crew"]} != original:
            raise ValueError("Crew assignments differ from the pinned contract")
        if selected["crew"] != original["crew"] and not any(
            change.get("role") == original["role"]
            and change.get("from") == original["crew"]
            and change.get("to") == selected["crew"]
            for change in run.get("coordination", {}).get("reassignments", [])
        ):
            raise ValueError("Missing retained reassignment evidence")
    tasks = [task for task in actual if task["role"] == role]
    if len(tasks) != 1:
        raise ValueError("Role has no unique capability assignment")
    task = tasks[0]
    if not run["evidence"].get(task["evidence"]):
        raise ValueError("Assignment dependency evidence is missing")
    # The implementer receives the lead's actual decision; reviewers receive the
    # Core-graded candidate, not an agent's assertion that verification succeeded.
    if (
        role == "implementer"
        and run["evidence"]["implementing"].get("output", {}).get("decision") == "abstain"
    ):
        raise ValueError("Lead declined implementation")
    return copy.deepcopy(task)
