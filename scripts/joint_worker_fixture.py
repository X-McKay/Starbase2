"""Integration-only worker checkpoints; never loaded by the product worker."""

import asyncio
import os
from pathlib import Path

from starbase_runtime.connection import connect
from starbase_runtime.joint_activities import joint_finish, joint_member
from starbase_runtime.joint_dispatch import reconcile_joint, register_joint
from starbase_runtime.joint_workflow import ReadinessJoint
from temporalio import activity
from temporalio.worker import Worker


@activity.defn(name="joint_member")
async def checkpoint_member(input: dict) -> dict:
    output = await joint_member(input)
    marker = Path(os.environ["STARBASE_JOINT_CHECKPOINT"])
    if (
        input["id"] == "restart"
        and input["task"]["id"] == "r0-lead"
        and not await asyncio.to_thread(marker.exists)
    ):
        await asyncio.to_thread(
            marker.write_text, "Response retained; activity acknowledgement intentionally paused\n"
        )
        await asyncio.sleep(180)
    return output


async def main():
    client = await connect()
    await register_joint()
    async with Worker(
        client,
        task_queue="joint-integration",
        workflows=[ReadinessJoint],
        activities=[checkpoint_member, joint_finish],
        max_concurrent_activities=4,
    ):
        while True:
            await reconcile_joint(client, "joint-integration")
            await asyncio.sleep(0.2)


if __name__ == "__main__":
    asyncio.run(main())
