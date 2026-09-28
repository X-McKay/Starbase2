"""Additive durable verification workflow; existing V7 mission histories stay intact."""

from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy
from temporalio.exceptions import ActivityError

with workflow.unsafe.imports_passed_through():
    from .sdlc_verification import (
        verification_abort,
        verification_execute,
        verification_finish,
        verification_pending,
        verification_repair,
        verification_review,
        verification_status,
        verification_update,
    )


@workflow.defn(name="RepositoryVerificationV7")
class RepositoryVerification:
    @workflow.run
    async def run(self, input: dict) -> dict:
        async def call(fn, value, seconds=90, attempts=2):
            return await workflow.execute_activity(
                fn,
                value,
                start_to_close_timeout=timedelta(seconds=seconds),
                retry_policy=RetryPolicy(maximum_attempts=attempts),
            )

        try:
            await call(verification_pending, input)
            verified = await call(verification_execute, input, 150)
            status = await call(verification_status, input)
            updated = None
            if verified["outcome"] == "failed":
                feedback = None
                for number in range(3):
                    task = input | {"round": number, "feedback": feedback}
                    proposal = await call(verification_repair, task, 320, 1)
                    if proposal.get("aborted"):
                        return {"status": "blocked"}
                    reviewed = await call(verification_review, task, 160, 1)
                    if reviewed["accepted"]:
                        updated = await call(verification_update, input, 180)
                        break
                    if not reviewed["continue"]:
                        return {"status": "blocked"}
                    feedback = reviewed["feedback"]
                else:
                    return await call(verification_abort, input)
            return await call(
                verification_finish, input | {"status_receipt": status, "update": updated}
            )
        except ActivityError:
            return await call(verification_abort, input)
