"""Read-only content inventory; prints JSON, never deletes or reads credentials.

Sizes are logical file bytes, not allocated disk space. Classification is a
retention hint, not a dependency analysis or permission to remove a file.
"""

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOTS = ("art", "apps/world/art", "apps/world/buildings/art", "evidence", "meshy_output", ".local")


def main():
    tracked = set(subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0"))
    files = []
    for base in ROOTS:
        for path in sorted((ROOT / base).rglob("*")):
            if path.is_symlink() or not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            suffix = path.relative_to(ROOT / base).parts
            group = base + ("/" + suffix[0] if len(suffix) > 1 else "")
            if re.search(r"\.blend\d+$", path.name):
                retention = "backup-review"
            elif base == "meshy_output":
                retention = "retain-rebuild-input-and-ledger"
            elif base == ".local":
                retention = "local-review-required-not-all-cache"
            elif base == "evidence":
                retention = "retain-until-evidence-review"
            else:
                retention = "retain-source-or-runtime"
            files.append(
                dict(
                    path=relative,
                    bytes=path.stat().st_size,
                    tracked=relative in tracked,
                    group=group,
                    retention=retention,
                )
            )
    groups = {}
    for item in files:
        group = groups.setdefault(item["group"], dict(files=0, bytes=0, tracked_files=0))
        group["files"] += 1
        group["bytes"] += item["bytes"]
        group["tracked_files"] += int(item["tracked"])
    print(
        json.dumps(
            dict(schema_version=1, size_unit="logical bytes", groups=groups, files=files), indent=2
        )
    )


if __name__ == "__main__":
    main()
