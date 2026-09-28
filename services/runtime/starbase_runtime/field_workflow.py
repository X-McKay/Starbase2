"""Additive workflow type; existing v1/v2/v3 histories retain their implementations."""

from datetime import timedelta
from hashlib import sha256

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from .field import field_advice, field_analyze, field_capture, field_finish, field_tick


@workflow.defn(name="FieldObservationV4")
class FieldObservation:
    @workflow.run
    async def run(self, input: dict) -> dict:
        await workflow.execute_activity(
            field_capture,
            input["id"],
            start_to_close_timeout=timedelta(seconds=100),
            retry_policy=RetryPolicy(maximum_attempts=2),
        )
        report = await workflow.execute_activity(
            field_analyze,
            input["id"],
            start_to_close_timeout=timedelta(seconds=120),
            retry_policy=RetryPolicy(maximum_attempts=2),
        )
        if input["inference"]:
            report["advisory"] = await workflow.execute_activity(
                field_advice,
                {"id": input["id"], "report": report},
                start_to_close_timeout=timedelta(seconds=70),
                retry_policy=RetryPolicy(maximum_attempts=1),
            )
        return await workflow.execute_activity(
            field_finish,
            {"id": input["id"], "report": report},
            start_to_close_timeout=timedelta(seconds=15),
            retry_policy=RetryPolicy(maximum_attempts=3),
        )


@workflow.defn(name="FieldDutyV4")
class FieldDuty:
    @workflow.run
    async def run(self, input: dict) -> None:
        staggered = input["id"].startswith("repo-") and workflow.patched(
            "repository-duty-stagger-v1"
        )
        for iteration in range(100):
            delay = input["interval_seconds"]
            if staggered and iteration == 0:
                delay = repository_initial_delay(input["id"], delay, int(workflow.time()))
            await workflow.sleep(timedelta(seconds=delay))
            await workflow.execute_activity(
                field_tick,
                {
                    "id": input["id"],
                    "generation": input["generation"],
                    "tick": int(workflow.time()),
                },
                start_to_close_timeout=timedelta(seconds=10),
                retry_policy=RetryPolicy(maximum_attempts=2),
            )
        workflow.continue_as_new(input)


def repository_initial_delay(identity: str, interval: int, timestamp: int) -> int:
    """Stable phase across restarts/continue-as-new; never catch up missed ticks."""
    phase = int.from_bytes(sha256(identity.encode()).digest()[:8], "big") % interval
    return (phase - timestamp) % interval or interval
