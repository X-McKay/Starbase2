"""Checksum-pinned tools, installed only under .local; no global config writes."""

import hashlib
import io
import json
import platform
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "fixtures/readiness"
TOOLCHAIN = json.loads((FIXTURES / "toolchain.json").read_text())
TOOLS = ROOT / ".local/readiness-tools"


def prepare() -> None:
    if (platform.system(), platform.machine()) != ("Darwin", "arm64"):
        raise RuntimeError("This initial lab toolchain is pinned for macOS arm64 only")
    TOOLS.mkdir(parents=True, exist_ok=True)
    for name in ("kind", "flux"):
        spec = TOOLCHAIN[name]
        archive = TOOLS / (name + ".download")
        if not archive.exists():
            with urllib.request.urlopen(spec["url"], timeout=60) as response:
                payload = response.read(100_000_001)
            if len(payload) > 100_000_000:
                raise ValueError("Tool download exceeds budget")
            archive.write_bytes(payload)
        payload = archive.read_bytes()
        if hashlib.sha256(payload).hexdigest() != spec["sha256"]:
            raise ValueError(f"{name}: checksum mismatch; retained failed download at {archive}")
        if name == "flux":
            with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as bundle:
                member = bundle.getmember("flux")
                if not member.isfile() or member.size > 150_000_000:
                    raise ValueError("Invalid Flux executable archive")
                stream = bundle.extractfile(member)
                assert stream is not None
                payload = stream.read()
        (TOOLS / name).write_bytes(payload)
        (TOOLS / name).chmod(0o700)
    print("Pinned kind and Flux tools are ready.")


if __name__ == "__main__":
    prepare()
