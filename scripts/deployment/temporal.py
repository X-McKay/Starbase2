"""Namespace ownership and retention via the official SDK; no default namespace mutation."""

import asyncio
import time
from datetime import timedelta

from google.protobuf.duration_pb2 import Duration
from starbase_runtime.connection import connect
from temporalio.api.enums.v1 import NamespaceState
from temporalio.api.operatorservice.v1 import DeleteNamespaceRequest
from temporalio.api.workflowservice.v1 import (
    CountWorkflowExecutionsRequest,
    DescribeNamespaceRequest,
    RegisterNamespaceRequest,
)
from temporalio.service import RPCError, RPCStatusCode


async def namespace(c: dict, operation: str) -> dict:
    client = await connect()
    name = c["temporal_namespace"]
    try:
        result = await client.workflow_service.describe_namespace(
            DescribeNamespaceRequest(namespace=name), retry=False, timeout=timedelta(seconds=20)
        )
    except RPCError as e:
        if e.status != RPCStatusCode.NOT_FOUND or operation != "ensure":
            raise
        await client.workflow_service.register_namespace(
            RegisterNamespaceRequest(
                namespace=name,
                description="Starbase2 fresh production installation",
                workflow_execution_retention_period=Duration(seconds=c["retention_days"] * 86400),
                data={"starbase2-installation": c["installation"]},
            ),
            retry=False,
            timeout=timedelta(seconds=20),
        )
        result = await client.workflow_service.describe_namespace(
            DescribeNamespaceRequest(namespace=name), retry=False, timeout=timedelta(seconds=20)
        )
    if result.namespace_info.data.get("starbase2-installation") != c["installation"]:
        raise ValueError("Refusing to adopt or change an unowned Temporal namespace")
    if result.namespace_info.state != NamespaceState.NAMESPACE_STATE_REGISTERED:
        raise ValueError("Temporal namespace is not registered/active")
    retention = result.config.workflow_execution_retention_ttl.seconds
    if retention != c["retention_days"] * 86400:
        raise ValueError("Retention differs; review/update it explicitly before proceeding")
    # Namespace registration reaches frontend/visibility caches asynchronously.
    # Retry only this read-only NOT_FOUND condition, with a bounded deadline.
    deadline = time.monotonic() + 30
    while True:
        try:
            count = await client.workflow_service.count_workflow_executions(
                CountWorkflowExecutionsRequest(namespace=name, query='ExecutionStatus = "Running"'),
                retry=False,
                timeout=timedelta(seconds=20),
            )
            break
        except RPCError as e:
            if e.status != RPCStatusCode.NOT_FOUND or time.monotonic() >= deadline:
                raise
            await asyncio.sleep(1)
    if operation == "delete":
        if count.count:
            raise ValueError("Open workflows remain; pause duties and drain/cancel before deleting")
        await client.operator_service.delete_namespace(
            DeleteNamespaceRequest(namespace=name), retry=False, timeout=timedelta(seconds=20)
        )
    return {
        "namespace": name,
        "retention_seconds": retention,
        "open_workflows": count.count,
        "operation": operation,
    }


async def export_histories(c: dict, directory) -> None:
    import hashlib
    import json

    from .database import private_write

    status = await namespace(c, "check")
    if status["open_workflows"]:
        raise ValueError("Pause duties and drain open workflows before exporting")
    client = await connect()
    target = directory / "temporal"
    target.mkdir(mode=0o700, exist_ok=False)
    files = {}
    async for execution in client.list_workflows():
        if len(files) >= 10000:
            raise ValueError("History export exceeds 10000 runs; retain partial export and review")
        identity = hashlib.sha256((execution.id + ":" + execution.run_id).encode()).hexdigest()
        history = await client.get_workflow_handle(
            execution.id, run_id=execution.run_id
        ).fetch_history()
        content = history.to_json()
        name = identity + ".json"
        private_write(target / name, content)
        files[name] = hashlib.sha256(content.encode()).hexdigest()
    private_write(
        target / "manifest.json",
        json.dumps(
            {
                "installation": c["installation"],
                "namespace": c["temporal_namespace"],
                "files": files,
                "purpose": "For audit/replay, not an importable Temporal persistence backup",
            },
            indent=2,
        ),
    )
