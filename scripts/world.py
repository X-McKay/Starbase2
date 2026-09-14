"""Import the native project before launching; Godot can log errors and exit zero."""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    project = ROOT / "apps/world"
    result = subprocess.run(
        ["godot", "--headless", "--path", str(project), "--editor", "--import", "--quit"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
        check=False,
    )
    print(result.stdout, end="", flush=True)
    if result.returncode or "ERROR:" in result.stdout or "Parse Error" in result.stdout:
        raise SystemExit("World import failed; inspect the errors above. Game was not launched.")
    raise SystemExit(subprocess.call(["godot", "--path", str(project), *sys.argv[1:]], cwd=ROOT))


if __name__ == "__main__":
    main()
