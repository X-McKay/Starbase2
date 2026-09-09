"""Build immutable release candidates from a clean checkout; never pushes images."""

import argparse
import json
import re
import subprocess
from pathlib import Path

from .render import ROOT


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("inputs", type=Path)
    p.add_argument("--engine", choices=["docker", "podman"], default="docker")
    p.add_argument("--execute", action="store_true")
    args = p.parse_args()
    data = json.loads(args.inputs.read_text())
    if set(data) != {"platform", "registry", "rust", "base", "python", "uv"}:
        raise ValueError("Unexpected build input keys")
    if data["platform"] not in {"linux/amd64", "linux/arm64"}:
        raise ValueError("Explicit supported Linux platform required")
    for k in ("rust", "base", "python", "uv"):
        if not re.fullmatch(r"[a-zA-Z0-9./:_-]+@sha256:[a-f0-9]{64}", data[k]):
            raise ValueError(f"{k} must be pinned by verified digest")
    if not re.fullmatch(r"[a-zA-Z0-9.:_-]+(?:/[a-zA-Z0-9._-]+)*/starbase2", data["registry"]):
        raise ValueError("Registry/repository must end in the starbase2 namespace")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT):
        raise ValueError(
            "Release builds require a clean committed checkout, including untracked files"
        )
    for component, bindings in (
        ("core", {"RUST_IMAGE": "rust", "BASE_IMAGE": "base"}),
        ("runtime", {"PYTHON_IMAGE": "python", "UV_IMAGE": "uv"}),
    ):
        tag = f"{data['registry']}/{component}:{revision}"
        command = [
            args.engine,
            "build",
            "--platform",
            data["platform"],
            "--pull=always",
            "--label",
            f"org.opencontainers.image.revision={revision}",
            "--file",
            f"deploy/{component}.Dockerfile",
            "--tag",
            tag,
        ]
        for key, value in bindings.items():
            command += ["--build-arg", f"{key}={data[value]}"]
        command.append(".")
        print(" ".join(command), flush=True)
        if args.execute:
            subprocess.run(command, cwd=ROOT, check=True, timeout=1800)
    print(
        "Images are local only. Publish through an authorized "
        "release workflow, then record registry digests."
    )


if __name__ == "__main__":
    main()
