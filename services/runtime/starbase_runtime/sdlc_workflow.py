"""Durable autonomous SDLC team; one-shot model calls and reconciled publication."""

from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy
from temporalio.exceptions import ActivityError

with workflow.unsafe.imports_passed_through():
    from .sdlc_runtime import (
        sdlc_abort,
        sdlc_finish,
        sdlc_follow,
        sdlc_implement,
        sdlc_lead,
        sdlc_prepare,
        sdlc_publish,
        sdlc_review,
    )


@workflow.defn(name="RepositorySdlcV7")
class RepositorySdlc:
    @workflow.run
    async def run(self, identity: str) -> dict:
        async def call(fn, value, seconds=160, attempts=1):
            return await workflow.execute_activity(
                fn,
                value,
                start_to_close_timeout=timedelta(seconds=seconds),
                retry_policy=RetryPolicy(maximum_attempts=attempts),
            )

        try:
            await call(sdlc_prepare, identity, 120, 2)
            lead = await call(sdlc_lead, identity)
            if not lead["continue"]:
                return {"status": "blocked"}
            feedback = None
            for round_number in range(3):
                await call(
                    sdlc_implement,
                    {
                        "id": identity,
                        "round": round_number,
                        "lead": lead["lead"],
                        "feedback": feedback,
                    },
                    200,
                )
                review = await call(sdlc_review, {"id": identity, "round": round_number})
                if review["accepted"]:
                    break
                if not review["continue"]:
                    return {"status": "blocked"}
                feedback = review["feedback"]
            else:
                return await call(sdlc_abort, identity, 20, 2)
            receipt = await call(sdlc_publish, identity, 180, 2)
            ci = {"status": "unknown"}
            for _ in range(30):
                ci = await call(sdlc_follow, {"id": identity, "receipt": receipt}, 30, 2)
                if ci.get("status") in {"passed", "failed"}:
                    break
                await workflow.sleep(timedelta(seconds=10))
            return await call(sdlc_finish, {"id": identity, "ci": ci}, 20, 2)
        except ActivityError:
            return await call(sdlc_abort, identity, 20, 2)
