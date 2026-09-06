"""Readiness measures successful reconciliation, not merely a living process."""

import json
import time
import urllib.request


def main() -> None:
    with urllib.request.urlopen("http://127.0.0.1:8787/v2/snapshot", timeout=5) as r:
        snapshot = json.load(r)
    # A local heartbeat file is written only after successful reconciliation.
    from pathlib import Path

    seen = float(Path("/tmp/starbase2-worker-heartbeat").read_text())
    if time.time() - seen > 30 or not snapshot:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
