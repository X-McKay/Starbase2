"""Isolated integration worker for the local Trainer and diagnostic crew."""

import asyncio
import os
from pathlib import Path

from starbase_runtime.connection import connect
from starbase_runtime.joint_activities import joint_finish, joint_member
from starbase_runtime.joint_dispatch import reconcile_joint, register_joint
from starbase_runtime.joint_workflow import ReadinessJoint
from starbase_runtime.learning import (
    learning_admit,
    learning_finish,
    learning_poll,
    learning_propose,
    reconcile_learning,
)
from starbase_runtime.learning_workflow import LearningPractice
from temporalio import activity
from temporalio.worker import Worker


@activity.defn(name="learning_propose")
async def checkpoint_proposal(cycle_id: str) -> dict:
    output = await learning_propose(cycle_id)
    marker_path = os.environ.get("STARBASE_LEARNING_CHECKPOINT")
    if marker_path:
        marker = Path(marker_path)
        if not await asyncio.to_thread(marker.exists):
            await asyncio.to_thread(marker.write_text, cycle_id)
            await asyncio.sleep(180)
    return output


async def main():
    client = await connect()
    await register_joint()
    async with Worker(
        client,
        task_queue="learning-integration",
        workflows=[ReadinessJoint, LearningPractice],
        activities=[
            joint_member,
            joint_finish,
            checkpoint_proposal,
            learning_admit,
            learning_poll,
            learning_finish,
        ],
        max_concurrent_activities=4,
    ):
        while True:
            await reconcile_joint(client, "learning-integration")
            await reconcile_learning(client, "learning-integration")
            await asyncio.sleep(0.3)


if __name__ == "__main__":
    asyncio.run(main())
