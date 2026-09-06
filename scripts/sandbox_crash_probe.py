"""Check process-group loss and coordinator-only loss using refreshed runtime status."""

import asyncio
import json
import os
import platform
import signal
import sys
import time

from starbase_runtime.sandbox import ROOT, command, remove

DESTINATION = ROOT / "evidence/sandbox-qualification" / platform.system().lower()


async def probe(group: bool) -> dict:
    name = "sb-crash-group" if group else "sb-crash-coordinator"
    started = time.monotonic()
    p = await asyncio.create_subprocess_exec(
        sys.executable,
        "-c",
        f"""import asyncio
from starbase_runtime.sandbox import run
asyncio.run(run({name!r}, "import time; time.sleep(60)"))
""",
        start_new_session=True,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL,
    )
    observations = []
    try:
        for _ in range(40):
            status = await command("status", "--format", "json", name)
            if status[0] == 0 and json.loads(status[1])["status"] == "Running":
                ping = await command("ping", name)
                if ping[0] == 0:
                    break
            await asyncio.sleep(0.1)
        else:
            raise AssertionError("VM did not start")
        if group:
            os.killpg(p.pid, signal.SIGKILL)
        else:
            p.kill()
        await p.wait()
        while time.monotonic() - started < 38:
            # `status` alone can be stale after abrupt death. Ping refreshes the
            # runtime's liveness classification; it does not touch the idle timer.
            ping = await command("ping", name)
            status = await command("status", "--format", "json", name)
            state = json.loads(status[1])["status"] if status[0] == 0 else "Missing"
            observations.append(
                {
                    "seconds": round(time.monotonic() - started, 3),
                    "status": state,
                    "ping_code": ping[0],
                    "ping_detail": (ping[1] + ping[2]).decode(),
                }
            )
            await asyncio.to_thread(
                (DESTINATION / f"{name}.json").write_text,
                json.dumps(observations, indent=2) + "\n",
            )
            if state in {"Stopped", "Crashed", "Missing"} and ping[0] != 0:
                return {
                    "passed": True,
                    "elapsed_seconds": round(time.monotonic() - started, 3),
                    "observations": observations,
                    "process_group_killed": group,
                }
            await asyncio.sleep(1)
        raise AssertionError("VM remained live after configured lifetime")
    finally:
        if p.returncode is None:
            p.kill()
            await p.wait()
        await remove(name)


async def main() -> None:
    await asyncio.to_thread(DESTINATION.mkdir, parents=True, exist_ok=True)
    result = {}
    for label, group in [("process_group", True), ("coordinator_only", False)]:
        result[label] = await probe(group)
        print(label, result[label]["elapsed_seconds"], flush=True)
        await asyncio.to_thread(
            (DESTINATION / "crash.json").write_text,
            json.dumps(result, indent=2) + "\n",
        )


if __name__ == "__main__":
    asyncio.run(main())
