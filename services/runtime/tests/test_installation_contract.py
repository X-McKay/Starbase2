"""Supported additive v2 rollout: old snapshots and future additive fields."""

import json
from pathlib import Path

from starbase_runtime.operations_contract import OperationsSnapshot


def test_installation_metadata_is_optional_and_additive():
    root = Path(__file__).resolve().parents[3]
    payload = json.loads((root / "contracts/fixtures/operations-installation.json").read_text())
    current = OperationsSnapshot.model_validate(payload)
    assert current.installation is not None
    assert current.installation.id == "fixture-installation"
    assert current.installation.capabilities.field.enabled
    assert not current.worker.available
    payload["installation"]["future_field"] = "ignored by older reader"
    future = OperationsSnapshot.model_validate(payload)
    assert future.installation is not None
    assert future.installation.id == "fixture-installation"
    del payload["installation"]
    assert OperationsSnapshot.model_validate(payload).installation is None
