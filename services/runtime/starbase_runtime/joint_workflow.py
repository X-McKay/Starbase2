"""V5 history: bounded adaptive lead/member handoffs with concurrent specialists."""

import asyncio
from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy
from temporalio.exceptions import ActivityError

with workflow.unsafe.imports_passed_through():
    from .joint import GRANT_TOKENS, MAX_ROUNDS, JointPlan
    from .joint_activities import joint_finish, joint_member


@workflow.defn(name="ReadinessJointV5")
class ReadinessJoint:
    @workflow.run
    async def run(self, input: dict) -> dict:
        async def member(task):
            return await workflow.execute_activity(
                joint_member,
                {"id": input["id"], "task": task},
                start_to_close_timeout=timedelta(seconds=90),
                retry_policy=RetryPolicy(maximum_attempts=2),
            )

        decision, reason = None, "Round budget exhausted"
        seen: set[tuple[str, str]] = set()
        for round_number in range(MAX_ROUNDS):
            try:
                lead = await member(
                    {
                        "id": f"r{round_number}-lead",
                        "role": "lead",
                        "focus": "overview",
                        "round": round_number,
                        "question": "Choose useful specialist work or a bounded final proposal",
                        "tokens": GRANT_TOKENS,
                    }
                )
                if lead["status"] != "completed":
                    reason = "Lead response failed or is unknown"
                    break
                plan = JointPlan.model_validate(lead["output"])
                if plan.decision is not None:
                    decision, reason = plan.decision.model_dump(mode="json"), plan.rationale
                    break
                # Simulation evidence is immutable. Rewording a question cannot create new evidence.
                keys = {(t.role, t.focus) for t in plan.tasks}
                if keys & seen:
                    reason = "Repeated member request without progress"
                    break
                seen.update(keys)
                results = await asyncio.gather(
                    *[
                        member(
                            {
                                "id": f"r{round_number}-{t.role}",
                                "round": round_number,
                                "tokens": GRANT_TOKENS,
                                **t.model_dump(mode="json"),
                            }
                        )
                        for t in plan.tasks
                    ],
                    return_exceptions=True,
                )
                if any(isinstance(result, BaseException) for result in results):
                    reason = (
                        "Member admission or execution failed; retained results remain inspectable"
                    )
                    break
            except ActivityError:
                reason = "Lead admission or execution failed"
                break
        return await workflow.execute_activity(
            joint_finish,
            {"id": input["id"], "decision": decision, "reason": reason},
            start_to_close_timeout=timedelta(seconds=15),
            retry_policy=RetryPolicy(maximum_attempts=3),
        )
