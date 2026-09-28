"""Durable orchestration of a bounded public practice comparison."""

from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy
from temporalio.exceptions import ActivityError

with workflow.unsafe.imports_passed_through():
    from .learning import learning_admit, learning_finish, learning_poll, learning_propose


@workflow.defn(name="LearningPracticeV6")
class LearningPractice:
    @workflow.run
    async def run(self, cycle_id: str) -> dict:
        async def call(fn, value, seconds=15):
            return await workflow.execute_activity(
                fn,
                value,
                start_to_close_timeout=timedelta(seconds=seconds),
                retry_policy=RetryPolicy(maximum_attempts=2),
            )

        try:
            cycle = await call(learning_propose, cycle_id, 90)
            if cycle.get("candidate") is not None and cycle["state"] != "cancelled":
                for slot in cycle["trial_order"]:
                    mission = await call(learning_admit, {"id": cycle_id, "slot": slot})
                    while mission["state"] not in {"completed", "failed", "cancelled"}:
                        await workflow.sleep(3)
                        mission = await call(learning_poll, mission["id"])
        except ActivityError:
            # Core retains the failure and independently distinguishes incomplete evidence.
            pass
        return await call(learning_finish, cycle_id)
