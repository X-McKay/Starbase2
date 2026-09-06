"""Read-only Python review. Repository code is data and is never executed."""

import hashlib
import io
import json
import os
import subprocess
import sys
import time
import tokenize
from pathlib import Path

PROFILES = {
    "surveyor-v1": "B006,E722,S307,S602,S506,S301,S501",
    "surveyor-v2": "B006,E722,S307,S602,S506,S301,S501,S113",
    "surveyor-regressed": "B006,E722,S602,S506,S301,S501",
}
EXCLUDE = {".git", ".local", ".venv", "node_modules", "target", "__pycache__", ".godot"}
ROOT = Path(__file__).resolve().parents[3]


def digest(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    ).hexdigest()


def redact(source: str) -> str:
    """Mask literal contents and comments, preserving line numbers and Python syntax.

    Deliberately excludes string-content-dependent rules. Invalid token streams are
    rejected, never retained verbatim. Identifiers remain: use only authorized roots.
    """
    tokens = []
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type == tokenize.STRING:
            prefix = token.string[: len(token.string) - len(token.string.lstrip("rubfRUBF"))]
            value = 'b""' if "b" in prefix.lower() else '""'
            value = "(" + value + "\n" * token.string.count("\n") + ")"
            token = token._replace(string=value)
        elif token.type in {tokenize.COMMENT, tokenize.FSTRING_MIDDLE}:
            token = token._replace(string=" " * len(token.string))
        tokens.append(token)
    return tokenize.untokenize(tokens)


def snapshot_directory(root: Path, max_files: int = 200, max_bytes: int = 1_000_000) -> dict:
    root = root.resolve(strict=True)
    files, skipped = [], []
    used = 0
    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(
            d
            for d in dirs
            if d not in EXCLUDE and not d.startswith(".") and not (Path(directory) / d).is_symlink()
        )
        if len(files) + len(skipped) >= max_files:
            skipped.append({"path": "*", "reason": "file budget; remaining directories omitted"})
            break
        for name in sorted(names):
            path = Path(directory) / name
            if path.suffix != ".py" or path.is_symlink():
                continue
            relative = path.relative_to(root).as_posix()
            if len(files) + len(skipped) >= max_files:
                skipped.append({"path": "*", "reason": "file budget; remaining files omitted"})
                break
            # O_NOFOLLOW also closes the leaf symlink replacement race.
            try:
                if len(files) >= max_files or path.stat().st_size + used > max_bytes:
                    skipped.append({"path": relative, "reason": "snapshot budget"})
                    continue
                fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd, "rb") as stream:
                    raw = stream.read(max_bytes - used + 1)
                if len(raw) + used > max_bytes:
                    raise ValueError("file changed beyond budget")
                used += len(raw)
                source = redact(raw.decode("utf-8"))
            except (OSError, UnicodeError, tokenize.TokenError, SyntaxError, ValueError):
                skipped.append({"path": relative, "reason": "unreadable or unparseable source"})
                continue
            files.append(
                {"path": relative, "source": source, "sha256": hashlib.sha256(raw).hexdigest()}
            )
    body = {"files": files, "skipped": skipped, "redaction": "literal-and-comment-v1"}
    return {**body, "digest": digest(body)}


def manifest(profile: str) -> dict:
    rules = PROFILES[profile]
    ruff = Path(sys.executable).parent / "ruff"
    body = {
        "profile": profile,
        "rules": rules,
        "engine": "ruff-0.16.6",
        "engine_sha256": hashlib.sha256(ruff.read_bytes()).hexdigest(),
        "implementation": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "lock": hashlib.sha256((ROOT / "uv.lock").read_bytes()).hexdigest(),
        "scope": "redacted Python structural checks; advisory findings",
    }
    return {"digest": digest(body), "manifest": body}


def scan_sources(snapshot: dict, profile: str) -> dict:
    started = time.monotonic()
    findings, errors = [], []
    for file in snapshot["files"]:
        result = subprocess.run(
            [
                str(Path(sys.executable).parent / "ruff"),
                "check",
                "--isolated",
                "--no-cache",
                "--select",
                PROFILES[profile],
                "--output-format",
                "json",
                "--stdin-filename",
                file["path"],
                "-",
            ],
            input=file["source"],
            text=True,
            capture_output=True,
            timeout=10,
            env={},
            cwd="/tmp",
            check=False,
        )
        if result.returncode not in {0, 1}:
            errors.append({"path": file["path"], "reason": "analysis engine failed"})
            continue
        for item in json.loads(result.stdout):
            if item["code"] in {None, "invalid-syntax"}:
                errors.append({"path": file["path"], "reason": "invalid Python syntax"})
                continue
            findings.append(
                {
                    "code": item["code"],
                    "file": file["path"],
                    "line": item["location"]["row"],
                    "message": item["message"],
                }
            )
    return {
        "snapshot_digest": snapshot["digest"],
        "findings": findings,
        "errors": errors + snapshot["skipped"],
        "files_reviewed": len(snapshot["files"]),
        "elapsed_ms": int((time.monotonic() - started) * 1000),
        "engine": "ruff-0.16.6",
        "model_calls": 0,
    }
