"""Predeclared exploratory paired pilot, never a qualification or promotion."""

import asyncio
import json
import time
from pathlib import Path

from starbase_runtime.inference import SYSTEM, configuration, explain
from starbase_runtime.review import digest

CASES = [("eval", ["S307"]), ("timeout", ["S113"]), ("clean", [])]
BASELINE_PROMPT = SYSTEM.replace(
    "\nUse the supplied authoritative rule meanings; do not invent different issues.", ""
)


def grade(case, response):
    if response["status"] != "available":
        return {"valid": False, "passed": None, "reason": "inference unavailable"}
    text = json.dumps(response["advice"]).lower()
    # Narrow observable factual checks, not semantic quality certification.
    if case == "eval":
        passed = "eval" in text and "pickle" not in text and "yaml" not in text
    elif case == "timeout":
        passed = "timeout" in text
    else:
        passed = ("no " in text or "none" in text) and "completely safe" not in text
    return {"valid": True, "passed": passed, "reason": "predeclared keyword factual smoke gate"}


async def main():
    output = Path(f"evidence/inference-pilot-{time.time_ns()}")
    output.mkdir(parents=True, exist_ok=False)
    protocol = {
        "question": "Does supplying rule meanings prevent code-to-meaning confusion?",
        "population": "three public synthetic rule-code cases",
        "design": "one paired observation per case and endpoint, alternating order",
        "endpoints": ["https://llm.almckay.io/v1", "http://127.0.0.1:11434/v1"],
        "models": ["Qwen3.6-35B-A3B-NVFP4", "qwen2.5-coder:7b"],
        "budget": "12 calls, at most 800 output tokens each; no retries",
        "metric": "per-case predeclared factual smoke gates, not broad quality",
        "stopping": "all 12 attempts, including failures; no optional stopping",
        "decision": "inconclusive for generalization regardless of pilot score",
        "cost": "unknown; user-authorized local/hosted development inference",
    }
    (output / "protocol.json").write_text(json.dumps(protocol, indent=2) + "\n")
    trials = []
    for endpoint, model in zip(protocol["endpoints"], protocol["models"], strict=True):
        for index, (case, codes) in enumerate(CASES):
            configs = []
            for context in [False, True]:
                c = {
                    **configuration(),
                    "endpoint": endpoint,
                    "model": model,
                    "rule_context": context,
                    "prompt": SYSTEM if context else BASELINE_PROMPT,
                }
                configs.append(c)
            if index % 2:
                configs.reverse()
            for config in configs:
                result = await explain(
                    {"findings": [{"code": c} for c in codes], "files_reviewed": 1, "errors": []},
                    config,
                )
                trial = {
                    "case": case,
                    "build": digest(config),
                    "configuration": config,
                    "result": result,
                    "grade": grade(case, result),
                }
                trials.append(trial)
                (output / "trials.json").write_text(json.dumps(trials, indent=2) + "\n")
                print(
                    json.dumps(
                        {
                            "model": model,
                            "case": case,
                            "context": config["rule_context"],
                            "grade": trial["grade"],
                            "ms": result["elapsed_ms"],
                        }
                    ),
                    flush=True,
                )
    print(str(output), flush=True)


if __name__ == "__main__":
    asyncio.run(main())
