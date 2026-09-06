"""Only the disposable, loopback PostgreSQL 18.3 rehearsal container."""

import argparse
import platform
import subprocess

DIGESTS = {
    "arm64": "0c24d31b13a9801233f136bc80e908bda9577ab7e9c622e572eebc13c186ed4d",
    "amd64": "a145910d7079e9fbf73e6df19d5fcca0ce59d747cf7d97ac772bff28c3759c32",
}
NAME = "starbase2-deploy-rehearsal"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=["start", "stop"])
    p.add_argument("--engine", choices=["podman", "docker"], default="podman")
    args = p.parse_args()
    if args.action == "stop":
        command = [args.engine, "rm", "--force", "--volumes", NAME]
    else:
        arch = {"aarch64": "arm64", "x86_64": "amd64"}.get(platform.machine(), platform.machine())
        if arch not in DIGESTS:
            raise ValueError("The rehearsal image supports amd64/arm64 only")
        command = [
            args.engine,
            "run",
            "--detach",
            "--name",
            NAME,
            "--publish",
            "127.0.0.1:55439:5432",
            "--env",
            "POSTGRES_HOST_AUTH_METHOD=trust",
            "--tmpfs",
            "/var/lib/postgresql",
            "docker.io/library/postgres@sha256:" + DIGESTS[arch],
        ]
    subprocess.run(command, check=True, timeout=180)


if __name__ == "__main__":
    main()
