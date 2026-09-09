"""Read-only prerequisite diagnosis; no network access or credential reads."""

import shutil
import subprocess
from pathlib import Path

for command, expected in [
    ("python3", "3.12.13"),
    ("cargo", "1.97.1"),
    ("uv", "0.12.7"),
    ("godot", "4.7.2"),
    ("just", "1.58.0"),
    ("git-lfs", "3.8.0"),
]:
    path = shutil.which(command)
    if path is None:
        print(f"MISSING {command}: run mise install and mise exec -- just doctor")
        continue
    version = subprocess.check_output([path, "--version"], text=True).strip()
    print(f"{'OK' if expected in version else 'VERSION MISMATCH'} {command}: {version}")
for path in [".venv/bin/python", ".local/tools/temporal", "target/debug/starbase-core"]:
    print(f"{'OK' if Path(path).exists() else 'MISSING'} {path}")
# Blender sources are Git LFS objects; a pointer file fails the character provenance checks.
tracked = subprocess.check_output(["git", "ls-files", "-z"], text=True).split("\0")
pointers = [
    name
    for name in tracked
    if name.endswith(".blend")
    and Path(name).is_file()
    and Path(name).stat().st_size < 1024
    and Path(name).read_bytes().startswith(b"version https://git-lfs.github.com/spec/")
]
if pointers:
    print(f"MISSING {len(pointers)} Git LFS objects ({pointers[0]}, ...): run git lfs pull")
else:
    print("OK Git LFS objects present for tracked .blend sources")
print("Runtime binds loopback ports 8787 and 7233. Integration uses 18787 and 17233.")
