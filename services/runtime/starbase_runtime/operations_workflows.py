"""Versioned durable workflows; v1 histories retain their original implementation."""

from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from .operations import duty_tick, review_advice, review_analyze, review_prepare, review_retain


@workflow.defn(name="RepositoryReviewV2")
class RepositoryReview:
    @workflow.run
    async def run(self, run_id: str) -> dict:
        input = await workflow.execute_activity(
            review_prepare,
            run_id,
            start_to_close_timeout=timedelta(seconds=60),
            schedule_to_close_timeout=timedelta(seconds=120),
            retry_policy=RetryPolicy(maximum_attempts=2),
        )
        report = await workflow.execute_activity(
            review_analyze,
            run_id,
            start_to_close_timeout=timedelta(seconds=60),
            schedule_to_close_timeout=timedelta(seconds=120),
            retry_policy=RetryPolicy(maximum_attempts=2),
        )
        if input["inference"] and input["target"] == "sample" and report["review"] is not None:
            report["review"]["advisory"] = await workflow.execute_activity(
                review_advice,
                report["review"],
                start_to_close_timeout=timedelta(seconds=70),
                retry_policy=RetryPolicy(maximum_attempts=1),
            )
        return await workflow.execute_activity(
            review_retain,
            {"id": run_id, "report": report},
            start_to_close_timeout=timedelta(seconds=60),
            schedule_to_close_timeout=timedelta(seconds=120),
            retry_policy=RetryPolicy(maximum_attempts=2),
        )


@workflow.defn(name="RecurringReviewV2")
class RecurringReview:
    @workflow.run
    async def run(self, input: dict) -> None:
        # Server-side durable timers; no process-memory scheduling or missed-tick burst.
        # Core rechecks current enabled state before each tick creates work.
        for _ in range(100):
            await workflow.sleep(timedelta(seconds=input["interval_seconds"]))
            await workflow.execute_activity(
                duty_tick,
                {"id": input["id"], "tick": str(int(workflow.time()))},
                start_to_close_timeout=timedelta(seconds=5),
                retry_policy=RetryPolicy(maximum_attempts=2),
            )
        workflow.continue_as_new(input)
