"""V3 repair orchestration; existing v1/v2 workflow histories remain supported."""

from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from .repair import repair_execute, repair_finish, repair_propose


@workflow.defn(name="IsolatedRepairV3")
class IsolatedRepair:
    @workflow.run
    async def run(self, run_id: str) -> dict:
        await workflow.execute_activity(
            repair_propose,
            run_id,
            start_to_close_timeout=timedelta(seconds=75),
            retry_policy=RetryPolicy(maximum_attempts=1),
        )
        for stage in ("baseline", "candidate"):
            await workflow.execute_activity(
                repair_execute,
                {"id": run_id, "stage": stage},
                start_to_close_timeout=timedelta(seconds=60),
                heartbeat_timeout=timedelta(seconds=5),
                cancellation_type=workflow.ActivityCancellationType.WAIT_CANCELLATION_COMPLETED,
                retry_policy=RetryPolicy(maximum_attempts=2),
            )
        return await workflow.execute_activity(
            repair_finish,
            run_id,
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=RetryPolicy(maximum_attempts=3),
        )
