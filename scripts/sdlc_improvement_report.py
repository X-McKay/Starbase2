"""Create an immutable advisory Trainer report from retained Core/probe JSON."""

import argparse
import json
from pathlib import Path

from starbase_runtime.review import digest
from starbase_runtime.sdlc_improvement import MAX_BYTES, derive_report, write_report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, default=Path(".local/sdlc-improvement"))
    args = parser.parse_args()
    snapshot: dict = {"missions": [], "verifications": []}
    for path in args.evidence:
        with path.open("rb") as stream:
            raw = stream.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError("Evidence file exceeds budget")
        value = json.loads(raw)
        if isinstance(value, list):
            for row in value:
                if isinstance(row, dict) and isinstance(row.get("mission"), dict):
                    mission = row["mission"]
                    snapshot["missions"].append(
                        mission
                        | {
                            "id": digest(value)[:12] + "/" + str(mission.get("id", "unknown")),
                            "retained_export_digest": digest(value),
                        }
                    )
        elif isinstance(value, dict) and "missions" in value:
            snapshot["missions"].extend(value["missions"])
            snapshot["verifications"].extend(value.get("verifications", []))
        else:
            raise ValueError("Expected Core snapshot or retained family probe records")
    print(write_report(args.output, derive_report(snapshot)))


if __name__ == "__main__":
    main()
