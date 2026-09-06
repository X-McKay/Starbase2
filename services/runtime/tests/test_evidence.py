"""Behavioral gates for the first slice, written before its implementation."""

import asyncio

from starbase_runtime.agent import build_manifest, review


def test_build_is_stable_and_variant_is_material():
    assert build_manifest("baseline") == build_manifest("baseline")
    assert build_manifest("baseline")["digest"] != build_manifest("regressed")["digest"]


def test_fake_agent_detects_fixture_and_abstains():
    assert asyncio.run(review("baseline", "return total / count"))["findings"]
    assert asyncio.run(review("baseline", "return total / max(count, 1)"))["findings"] == []
    assert asyncio.run(review("regressed", "return total / count"))["findings"] == []


def test_unknown_snapshot_version_cannot_dispatch(monkeypatch):
    from unittest.mock import Mock

    from starbase_runtime import worker
    from temporalio.client import Client

    async def snapshot(*args):
        return {"schema_version": 2, "simulation": True, "missions": []}

    monkeypatch.setattr(worker, "api", snapshot)
    import pytest

    with pytest.raises(ValueError, match="Unsupported"):
        asyncio.run(worker.reconcile(Mock(spec=Client)))


def test_additive_snapshot_fields_are_compatible():
    from starbase_runtime.contract import Snapshot

    snapshot = Snapshot.model_validate(
        {
            "schema_version": 1,
            "observed_at": 0.0,
            "simulation": True,
            "missions": [],
            "future_optional_field": "ignored",
        }
    )
    assert snapshot.missions == []
