from datetime import timedelta

from temporalio import workflow
from temporalio.common import RetryPolicy

with workflow.unsafe.imports_passed_through():
    from pydantic_ai.usage import UsageLimits

    from .activities import prepare, retain, run_trial
    from .agent import make_agent

baseline_agent = make_agent("baseline", durable=True)
candidate_agent = make_agent("regressed", durable=True)


@workflow.defn(name="SurveyorCampaignV1")
class SurveyorCampaign:
    __pydantic_ai_agents__ = [baseline_agent, candidate_agent]

    @workflow.run
    async def run(self, input: dict) -> dict:
        cases = await workflow.execute_activity(
            prepare,
            input,
            start_to_close_timeout=timedelta(seconds=40),
            schedule_to_close_timeout=timedelta(seconds=100),
            heartbeat_timeout=timedelta(seconds=3),
            cancellation_type=workflow.ActivityCancellationType.WAIT_CANCELLATION_COMPLETED,
            retry_policy=RetryPolicy(maximum_attempts=3),
        )
        trials = []
        for index, (case_id, source) in enumerate(cases):
            # Paired public controls, alternating order; never select the best repetition.
            builds = [input["baseline"], input["candidate"]]
            if index % 2:
                builds.reverse()
            for build in builds:
                if input["integration"]:
                    agent = baseline_agent if build["variant"] == "baseline" else candidate_agent
                    started = workflow.time()
                    result = await agent.run(source, usage_limits=UsageLimits(request_limit=1))
                    trial = {
                        "case_id": case_id,
                        "build_digest": build["digest"],
                        "findings": result.output.model_dump()["findings"],
                        "elapsed_ms": int((workflow.time() - started) * 1000),
                        "model": "function:surveyor-fixture-v1",
                        "requests": result.usage.requests,
                    }
                else:
                    trial = await workflow.execute_activity(
                        run_trial,
                        {"case_id": case_id, "source": source, **build},
                        start_to_close_timeout=timedelta(seconds=10),
                        schedule_to_close_timeout=timedelta(seconds=30),
                        retry_policy=RetryPolicy(maximum_attempts=2),
                    )
                trials.append(trial)
        return await workflow.execute_activity(
            retain,
            {"id": input["id"], "trials": trials},
            start_to_close_timeout=timedelta(seconds=5),
            schedule_to_close_timeout=timedelta(seconds=45),
            retry_policy=RetryPolicy(maximum_attempts=5),
        )
