import asyncio
from unittest.mock import AsyncMock

from starbase_runtime import worker


def test_legacy_reconciliation_failure_does_not_suppress_operations(monkeypatch):
    current = AsyncMock()
    monkeypatch.setenv("STARBASE_TOKEN_FILE", "/unused-test-token")
    monkeypatch.setattr(
        worker, "reconcile", AsyncMock(side_effect=RuntimeError("legacy unavailable"))
    )
    monkeypatch.setattr(worker, "reconcile_operations", current)
    client = AsyncMock()
    asyncio.run(worker.reconcile_all(client))
    current.assert_awaited_once_with(client, worker.QUEUE)
