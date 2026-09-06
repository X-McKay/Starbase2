"""Persistent loopback-only development FalkorDB; production reuses Kubani's service."""

import signal
import threading
from pathlib import Path

from redislite.falkordb_client import FalkorDB


def main():
    output = Path(__file__).resolve().parents[1] / ".local/memory"
    output.mkdir(parents=True, exist_ok=True)
    stopped = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stopped.set())
    db = FalkorDB(str(output / "memory.rdb"), serverconfig={"port": "16379", "bind": "127.0.0.1"})
    try:
        print(
            "Development FalkorDB at 127.0.0.1:16379; persistent .local/memory/memory.rdb",
            flush=True,
        )
        stopped.wait()
    finally:
        db.close()


if __name__ == "__main__":
    main()
