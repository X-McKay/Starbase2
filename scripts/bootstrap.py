"""Install locked dependencies and a checksum-pinned local Temporal CLI."""

import hashlib
import os
import platform
import shutil
import subprocess
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.8.3"
CHECKSUMS = {
    "darwin_arm64": "77c5bef1753ddfcdcaced2a2d44207aeced1c776e7bcbf94520c7911bd0c4080",
    "darwin_amd64": "0eed9a02008ba0d1c5417fc1aa706c9016166eae7216ae161ad95eccc6a775ca",
    "linux_arm64": "5972ce781d7f28644b353e4177007e7da8e48a316b8458267054b24de2308e09",
    "linux_amd64": "6f0afac1e9ddea71f480c43a49f5db5167a244c21db923707f069a79bcabdfea",
}


def main() -> None:
    os.chdir(ROOT)
    machine = {"aarch64": "arm64", "x86_64": "amd64"}.get(platform.machine(), platform.machine())
    target = f"{platform.system().lower()}_{machine}"
    if target not in CHECKSUMS:
        raise SystemExit("Bootstrap currently supports macOS/Linux ARM64 and x86-64.")
    tools = ROOT / ".local/tools"
    tools.mkdir(parents=True, exist_ok=True)
    name = f"temporal_cli_{VERSION}_{target}.tar.gz"
    archive = tools / name
    if not archive.exists():
        url = f"https://github.com/temporalio/cli/releases/download/v{VERSION}/{name}"
        print(f"Downloading Temporal {VERSION} ({target})", flush=True)
        with urllib.request.urlopen(url, timeout=60) as source, archive.open("wb") as dest:
            shutil.copyfileobj(source, dest)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != CHECKSUMS[target]:
        raise SystemExit(
            f"Checksum mismatch: {archive}. Inspect/remove this download before retrying."
        )
    with tarfile.open(archive) as tar:
        source = tar.extractfile("temporal")
        if source is None:
            raise SystemExit("Temporal executable absent from archive")
        with source, (tools / "temporal").open("wb") as dest:
            shutil.copyfileobj(source, dest)
    (tools / "temporal").chmod(0o755)
    env = {**os.environ, "UV_CACHE_DIR": str(ROOT / ".local/cache/uv")}
    subprocess.run(["uv", "sync", "--locked"], env=env, check=True)
    subprocess.run(["cargo", "build", "--locked"], check=True)
    print(
        "Bootstrap complete. Run just check, then just dev in one terminal "
        "and just world in another for the native app."
    )


if __name__ == "__main__":
    main()
