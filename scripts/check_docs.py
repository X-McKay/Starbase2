"""Check local documentation links, lifecycle status, IDs, and conflict markers.

Standard library only. Does not access the network or execute documented commands.
External links, semantic accuracy, and diagram rendering require separate review.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP = {".git", ".venv", "node_modules", "target", ".godot", ".local"}
STATUSES = {"draft", "proposed", "accepted", "deprecated", "superseded", "withdrawn"}
FENCE = re.compile(r"^```[^\n]*\n.*?^```\s*$", re.MULTILINE | re.DOTALL)
LINK = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def main() -> int:
    errors: list[str] = []
    seen: set[str] = set()
    files = sorted(p for p in ROOT.rglob("*.md") if not SKIP.intersection(p.parts))
    for path in files:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        if re.search(r"^(?:<{7}|={7}|>{7})(?: |$)", text, re.MULTILINE):
            errors.append(f"{rel}: conflict marker")
        body = FENCE.sub("", text)
        for target in LINK.findall(body):
            target = target.strip().split("#", 1)[0]
            if not target or re.match(r"(?:https?://|mailto:)", target):
                continue
            if not (path.parent / target).exists():
                errors.append(f"{rel}: broken link: {target}")
        if path.name == "SPEC.md" or "docs" in rel.parts:
            status = re.search(r"^Status:\s*([a-z]+)", text, re.MULTILINE)
            # Research is an evidence record, not a proposal/decision.
            if path.name != "research.md" and (not status or status[1] not in STATUSES):
                errors.append(f"{rel}: missing or invalid lifecycle status")
        for req in re.findall(r"\*\*(SBT-\d+):\*\*", text):
            if req in seen:
                errors.append(f"{rel}: duplicate requirement {req}")
            seen.add(req)
    for error in errors:
        print(error, file=sys.stderr)
    print(f"Checked {len(files)} Markdown files and {len(seen)} requirement IDs.")
    if not errors:
        print("Documentation checks passed.")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
