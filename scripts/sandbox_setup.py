"""Explicit pinned image preparation; missions never pull implicitly."""

import argparse
import asyncio

from starbase_runtime.sandbox import IMAGE, VERSION, command


async def main(pull: bool) -> None:
    code, output, error = await command("--version")
    if code or output.decode().strip().split()[-1].lstrip("v") != VERSION:
        raise SystemExit("Install microsandbox 0.6.14 using the upstream signed release.")
    print(output.decode().strip())
    code, output, error = await command("doctor")
    print((output + error).decode())
    if code:
        raise SystemExit(code)
    if pull:
        # Pull can take longer than the bounded control commands.
        import asyncio.subprocess

        from starbase_runtime.sandbox import environment, executable

        process = await asyncio.create_subprocess_exec(
            executable(), "image", "pull", IMAGE, env=environment()
        )
        if await process.wait():
            raise SystemExit("Pinned image pull failed")
    else:
        code, output, error = await command("image", "inspect", IMAGE)
        print((output + error).decode())
        if code:
            raise SystemExit("Pinned image absent; run just sandbox-prepare")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--pull", action="store_true")
    asyncio.run(main(parser.parse_args().pull))
