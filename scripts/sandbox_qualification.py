"""Bounded adversarial smoke probes, not a security certification."""

import asyncio
import json
import os
import platform
import tempfile
from pathlib import Path

from starbase_runtime.sandbox import POLICY, command, run

ROOT = Path(__file__).resolve().parents[1]
PROBES = {
    "isolation": """import os,json,socket
paths = [HOST_SENTINEL, "/grader.py", "/tests/hidden.json"]
r = {"host_files_absent": all(not os.path.exists(p) for p in paths),
     "unprivileged": os.getuid()==65534,
     "credential_absent": not any(k in os.environ for k in ["STARBASE_TOKEN_FILE",
       "STARBASE_SANDBOX_TEST_SECRET", "KUBECONFIG", "GITHUB_TOKEN",
       "STARBASE_FALKOR_PASSWORD_FILE"])}
targets=[("core", "127.0.0.1",8787),("host_gateway","192.168.127.1",8787),
         ("internet","1.1.1.1",443)]
for label,host,port in targets:
 try:
  socket.create_connection((host,port),timeout=0.4).close(); r[label+"_blocked"]=False
 except OSError: r[label+"_blocked"]=True
try:
 open("/program.py", "w").write("tamper"); r["input_readonly"]=False
except OSError: r["input_readonly"]=True
print(json.dumps(r))""",
    "memory": """import json
try:
 a=bytearray(200*1024*1024); print(json.dumps({"bounded":False}))
except MemoryError: print(json.dumps({"bounded":True}))""",
    "disk": """import json
try:
 with open("/tmp/flood", "wb") as f: f.write(b"x"*(9*1024*1024))
 print(json.dumps({"bounded":False}))
except OSError: print(json.dumps({"bounded":True}))""",
    "timeout": "while True: pass",
    "background": """import subprocess
subprocess.Popen(["python3","-c","import time; time.sleep(60)"])
print("spawned")""",
}


async def probes(sentinel: str) -> None:
    results = {}
    destination = ROOT / "evidence/sandbox-qualification" / platform.system().lower()
    await asyncio.to_thread(destination.mkdir, parents=True, exist_ok=True)
    for label, source in PROBES.items():
        result = await run(
            "sb-probe-" + label, source.replace("HOST_SENTINEL", repr(sentinel)), seconds=2
        )
        status = await command("status", "sb-probe-" + label)
        result["removed"] = status[0] != 0 and b"not found" in status[1] + status[2]
        if label in {"isolation", "memory", "disk"}:
            result["checks"] = json.loads(result["stdout"])
            result["passed"] = result["exit_code"] == 0 and all(result["checks"].values())
        elif label == "timeout":
            result["passed"] = result["exit_code"] != 0 and result["elapsed_ms"] < 12000
        else:
            result["passed"] = result["removed"]
        results[label] = result
        print(label, result["passed"], flush=True)
    task = asyncio.create_task(run("sb-probe-cancel", "import time; time.sleep(60)"))
    await asyncio.sleep(1)
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass
    status = await command("status", "sb-probe-cancel")
    results["cancellation"] = {"passed": status[0] != 0 and b"not found" in status[1] + status[2]}
    await asyncio.to_thread(
        (destination / "probes.json").write_text,
        json.dumps(
            {"platform": platform.platform(), "policy": POLICY, "results": results}, indent=2
        )
        + "\n",
    )
    assert all(r["passed"] and r.get("removed", True) for r in results.values()), results


def main():
    # A real host-only file makes the absence assertion meaningful on Linux and macOS.
    with tempfile.TemporaryDirectory(prefix="starbase-host-probe-") as directory:
        sentinel = Path(directory) / "host-only-canary"
        sentinel.write_text("synthetic qualification canary; no credentials")
        previous = os.environ.get("STARBASE_SANDBOX_TEST_SECRET")
        os.environ["STARBASE_SANDBOX_TEST_SECRET"] = "synthetic-must-not-cross"
        try:
            asyncio.run(probes(str(sentinel)))
        finally:
            if previous is None:
                os.environ.pop("STARBASE_SANDBOX_TEST_SECRET", None)
            else:
                os.environ["STARBASE_SANDBOX_TEST_SECRET"] = previous


if __name__ == "__main__":
    main()
