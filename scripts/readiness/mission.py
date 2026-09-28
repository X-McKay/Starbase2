"""One bounded crew mission in the owned local lab; scripted control by default."""

import argparse
import asyncio
import copy
import hashlib
import json
import signal
import time
from pathlib import Path

from pydantic_ai.messages import ModelMessagesTypeAdapter
from pydantic_ai.models import ModelRequestParameters
from pydantic_ai.models.wrapper import WrapperModel
from pydantic_ai.settings import ModelSettings
from starbase_runtime.readiness import (
    LIMITS,
    POLICY,
    Decision,
    FenceError,
    MissionSession,
    View,
    build_manifest,
    make_agent,
    make_qwen_model,
    scripted_model,
)

from .contract import Observation, digest, grade, manifest, scope_errors
from .run import Lab, functional
from .tools import ROOT, prepare

MISSION_CASES = {
    "route-mismatch": "repair",
    "healthy": "wait",
    "persistent-dependency": "abstain",
    "listening-but-broken": "abstain",
}


def model_configuration(mode: str) -> dict:
    if mode == "scripted":
        return {"mode": mode, "name": "function:readiness-scripted-v1", "endpoint": None}
    if mode != "inference":
        raise ValueError("Unknown model mode")
    from starbase_runtime.inference import configuration

    c = configuration()
    return {"mode": mode, "name": c["model"], "endpoint": c["endpoint"]}


class MissionLab(Lab):
    """Fence every subsequent command after admission, including multi-step publication."""

    session: MissionSession | None = None
    cancel_path: Path | None = None

    def call(self, *args, **kwargs):
        if self.cancel_path is not None and self.cancel_path.exists():
            raise FenceError("cancelled")
        if self.session is not None:
            self.session.guard()
        return super().call(*args, **kwargs)


class MissionPort:
    def __init__(self, lab: MissionLab, seed: dict, revision: str, fingerprint: str):
        self.lab, self.seed = lab, seed
        self.proposed = copy.deepcopy(seed)
        self.revision, self.fingerprint = revision, fingerprint
        self.observations: list[dict] = []

    def capture(self, view: View) -> dict:
        observation, raw = self.lab.observe(self.revision, self.fingerprint, time.monotonic())
        deployment = raw["deployment"]
        precondition = {
            "revision": observation.revision,
            "spec_digest": digest(deployment["spec"]),
            "generation": deployment["metadata"]["generation"],
            "deployment_uid": deployment["metadata"]["uid"],
            "fresh": observation.flux_current
            and observation.workload_current
            and observation.revision == self.revision,
        }
        data: dict = {"target": POLICY["target"], "view": view}
        if view == "manifest":
            container = deployment["spec"]["template"]["spec"]["containers"][0]
            data.update(
                probes={key: container[key] for key in ("readinessProbe", "livenessProbe")},
                ready=observation.ready,
                service_contract={
                    "/live": "process liveness",
                    "/ready": "dependency readiness",
                    "/work?value=<integer>": "return integer value * value + 1",
                },
            )
        elif view == "work":
            data.update(ready=observation.ready, responses=raw["answers"])
        elif view == "events":
            events = self.lab.get("events")["items"]
            data["events"] = [
                {
                    "reason": e.get("reason"),
                    "message": e.get("message", "")[:350],
                    "last_timestamp": e.get("lastTimestamp"),
                }
                for e in events
                if e.get("involvedObject", {}).get("uid")
                in {raw["pod"].get("metadata", {}).get("uid"), deployment["metadata"]["uid"]}
            ][-8:]
        elif view == "logs":
            pod = raw["pod"].get("metadata", {}).get("name")
            data["logs"] = (
                self.lab.kubectl(
                    "logs",
                    pod,
                    "-n",
                    "readiness-lab",
                    "-c",
                    "worker",
                    "--tail=25",
                    "--limit-bytes=2000",
                    "--timestamps=true",
                ).decode(errors="replace")
                if pod
                else "Current Pod unavailable"
            )
        self.observations.append({"view": view, "precondition": precondition, "raw": raw})
        self.lab.report["mission_observations"] = self.observations
        self.lab.save()
        return {"precondition": precondition, "data": data}

    async def observe(self, view: View) -> dict:
        return await asyncio.to_thread(self.capture, view)

    def publish(self, decision: Decision) -> dict:
        proposed = copy.deepcopy(self.seed)
        container = proposed["spec"]["template"]["spec"]["containers"][0]
        container["readinessProbe"]["httpGet"]["path"] = decision.readiness_path
        container["livenessProbe"]["httpGet"]["path"] = decision.liveness_path
        if scope_errors(self.seed, proposed):
            raise FenceError("ineligible")
        self.revision, self.fingerprint = self.lab.publish(proposed, "crew probe proposal")
        self.proposed = proposed
        self.lab.report["mission_proposal"] = {"manifest": proposed, "revision": self.revision}
        self.lab.save()
        return {"revision": self.revision, "manifest_digest": self.fingerprint}

    async def apply(self, proposal: Decision) -> dict:
        return await asyncio.to_thread(self.publish, proposal)

    def verify_sync(self, action: str) -> dict:
        activation = self.lab.wait_workload(self.fingerprint)
        samples = self.lab.sample(self.revision, self.fingerprint, 45, action != "abstain")
        verdict = grade(
            self.seed,
            self.proposed,
            self.revision,
            [Observation(**s["observation"]) for s in samples[-3:]],
            "escalate" if action == "abstain" else action,
        )
        self.lab.report["mission_verification"] = {
            "activation": activation,
            "samples": samples,
            "grade": verdict,
        }
        self.lab.save()
        return verdict

    async def verify(self, action: str) -> dict:
        return await asyncio.to_thread(self.verify_sync, action)


class RecordedModel(WrapperModel):
    """No automatic provider retries; persist every request and response separately."""

    def __init__(self, wrapped, session: MissionSession, live: bool):
        super().__init__(wrapped)
        self.session, self.live = session, live
        self.requests = 0
        self.tokens = 0

    async def request(
        self,
        messages,
        model_settings: ModelSettings | None,
        model_request_parameters: ModelRequestParameters,
    ):
        self.session.guard()
        if self.requests >= POLICY["model_requests"]:
            raise FenceError("model-request-budget-exceeded")
        # Conservative UTF-8 byte reservation, including tool schemas and framing.
        # Provider accounting is retained separately; unavailable accounting fences
        # future dispatch. This is not a monetary cost estimate or tokenizer proof.
        serialized = ModelMessagesTypeAdapter.dump_json(messages)
        schemas = json.dumps(
            [
                t.parameters_json_schema
                for t in [
                    *model_request_parameters.function_tools,
                    *model_request_parameters.output_tools,
                ]
            ]
        )
        reservation = (
            len(serialized) + len(schemas.encode()) + 1024 + POLICY["output_tokens_per_request"]
        )
        if self.live and self.tokens + reservation > POLICY["total_tokens"]:
            raise FenceError("model-token-reservation-exceeded")
        self.requests += 1
        item = {
            "request": self.requests,
            "reserved_tokens": reservation,
            "messages": json.loads(serialized),
            "state": "started",
        }
        self.session.record.setdefault("model_requests", []).append(item)
        self.session.save()
        start = time.monotonic()
        try:
            response = await self.wrapped.request(
                messages, model_settings, model_request_parameters
            )
            item.update(
                state="returned",
                reported_model=response.model_name,
                provider=response.provider_name,
                usage={
                    "input_tokens": response.usage.input_tokens,
                    "output_tokens": response.usage.output_tokens,
                },
                response=json.loads(ModelMessagesTypeAdapter.dump_json([response])),
            )
            self.tokens += response.usage.total_tokens
            if response.finish_reason == "length":
                raise FenceError("model-output-truncated")
            if self.live and (
                response.usage.input_tokens <= 0
                or response.usage.total_tokens > reservation
                or self.tokens > POLICY["total_tokens"]
            ):
                raise FenceError("provider-usage-unavailable-or-over-reservation")
            self.session.guard()
            return response
        except BaseException as error:
            item["error"] = type(error).__name__
            raise
        finally:
            item["elapsed_ms"] = round((time.monotonic() - start) * 1000)
            self.session.record["usage"] = {
                "requests": self.requests,
                "reported_tokens": self.tokens,
                "provider_calls": self.requests if self.live else 0,
                "cost_usd": None if self.live else 0,
            }
            self.session.save()


async def execute(
    lab: MissionLab,
    port: MissionPort,
    mode: str,
    variant: str = "baseline",
    case: str = "route-mismatch",
    expected_build: dict | None = None,
):
    from contextlib import AsyncExitStack

    config = model_configuration(mode)
    build = build_manifest(config, variant)
    if expected_build is not None and build != expected_build:
        raise RuntimeError("Build changed since campaign declaration")
    async with AsyncExitStack() as stack:
        model = scripted_model(MISSION_CASES[case])
        if mode == "inference":
            import httpx2
            from openai import AsyncOpenAI
            from pydantic_ai.providers.openai import OpenAIProvider

            http = await stack.enter_async_context(
                httpx2.AsyncClient(timeout=45, trust_env=False, follow_redirects=False)
            )
            sdk = AsyncOpenAI(
                base_url=config["endpoint"],
                api_key="development-no-key",
                max_retries=0,
                http_client=http,
            )
            model = make_qwen_model(config["name"], provider=OpenAIProvider(openai_client=sdk))
        for relative, expected in build["manifest"]["sources"].items():
            contents = (ROOT / relative).read_bytes()
            if hashlib.sha256(contents).hexdigest() != expected:
                raise RuntimeError("Build changed during admission")
            path = lab.output / "build-sources" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)
        session = MissionSession(port, lab.output / "mission.json", build)
        if lab.cancel_path is not None:
            session.cancel_paths.append(lab.cancel_path)
        lab.session = session
        previous_handlers = {}
        for sig in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[sig] = signal.signal(sig, lambda *_: session.cancelled.set())
        try:
            print("Crew investigating through bounded tools", flush=True)
            result = await make_agent(
                RecordedModel(model, session, mode == "inference"), variant
            ).run(
                "Assess this workload's readiness and useful work. Inspect the evidence, "
                "then propose a repair, wait, or abstain.",
                deps=session,
                usage_limits=LIMITS,
            )
            session.record["agent_messages"] = json.loads(result.all_messages_json())
            session.save()
            print("Crew decision: " + result.output.action, flush=True)
            await session.finish(result.output)
        except FenceError as error:
            session.record["state"] = str(error)
        except Exception as error:
            session.record["state"] = "invalid"
            session.record["error"] = type(error).__name__
        finally:
            session.save()
            lab.session = None  # Cleanup remains available despite expiry/cancellation.
            for sig, handler in previous_handlers.items():
                signal.signal(sig, handler)
        return session.record


def seed_observed(case: str, samples: list[dict]) -> bool:
    """Require the declared starting fault/control before admitting a Crew run."""
    for sample in samples:
        o = sample["observation"]
        if not (o["flux_current"] and o["workload_current"] and o["pod_uid"]):
            continue
        pod_works = functional(sample["answers"].get("pod", []))
        if case == "route-mismatch" and not o["ready"] and pod_works:
            return True
        if case == "healthy" and o["ready"] and o["functional"] is True:
            return True
        if case == "persistent-dependency" and not o["ready"] and o["functional"] is False:
            return True
        if case == "listening-but-broken" and o["ready"] and o["functional"] is False:
            return True
    return False


def run_trial(
    output: Path,
    mode: str = "scripted",
    variant: str = "baseline",
    case: str = "route-mismatch",
    expected_build: dict | None = None,
    cancel_path: Path | None = None,
) -> tuple[dict, dict]:
    if case not in MISSION_CASES:
        raise ValueError("Unsupported mission scenario")
    current_build = build_manifest(model_configuration(mode), variant)
    if expected_build is not None and current_build != expected_build:
        raise RuntimeError("Build changed before lab creation")
    prepare()
    lab = MissionLab(output)
    lab.cancel_path = cancel_path
    lab.report.update(mode="crew-mission-" + mode, scenario=case, variant=variant)
    (lab.private / "auth.json").write_text('{"auths":{}}\n')
    mission: dict = {}
    try:
        lab.setup()
        seed = manifest(case, lab.images["built-service"])
        revision, fingerprint = lab.publish(seed, "readiness mission seed")
        lab.wait_workload(fingerprint)
        before = lab.sample(revision, fingerprint, 12, False)
        if not seed_observed(case, before):
            raise RuntimeError("Declared initial condition was not observed")
        lab.report["mission_seed"] = {"manifest": seed, "revision": revision, "before": before}
        lab.save()
        port = MissionPort(lab, seed, revision, fingerprint)
        mission = asyncio.run(execute(lab, port, mode, variant, case, current_build))
        # Abstention never self-certifies. The evaluator independently gathers
        # a fixed window after the agent stops; it cannot dispatch mutations.
        if mission["state"] == "abstained":
            port.verify_sync("abstain")
        lab.report["mission_state"] = mission["state"]
        lab.report["model_calls"] = mission.get("usage", {}).get("provider_calls", 0)
        lab.report["status"] = "completed"
    except BaseException as error:
        lab.report["status"] = "invalid"
        lab.report["error"] = type(error).__name__
        lab.report["error_detail"] = str(error)
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            raise
    finally:
        lab.session = None
        lab.cancel_path = None
        try:
            lab.cleanup()
        except Exception:
            lab.report["cleanup"] = "failed"
            lab.report["status"] = "invalid"
        finally:
            lab.save()
    return mission, lab.report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New evidence directory; never resumed")
    parser.add_argument("--mode", choices=("scripted", "inference"), default="scripted")
    parser.add_argument("--variant", choices=("baseline", "runbook-v1"), default="baseline")
    parser.add_argument("--scenario", choices=tuple(MISSION_CASES), default="route-mismatch")
    args = parser.parse_args()
    mission, report = run_trial(args.output, args.mode, args.variant, args.scenario)
    from .campaign import score_trial

    score = score_trial(args.scenario, mission, report)
    print(
        json.dumps(
            {
                "score": score,
                "cleanup": report["cleanup"],
                "mission": str(args.output / "mission.json"),
            }
        )
    )
    if score["outcome"] != "pass":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
