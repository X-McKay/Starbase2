"""Process-pinned local profiles. New settings or Procedures require a new build."""

import hashlib
import os
from importlib.resources import files

PROFILES = {"legacy", "tools", "tools-thinking"}
PROFILE = os.environ.get("STARBASE_SDLC_AGENT_PROFILE", "legacy")
if PROFILE not in PROFILES:
    raise ValueError("Unknown installed SDLC profile")
NAMES = ("engineering", "review", "recovery")
_CONTENT = {name: files(__package__).joinpath(f"runbooks/{name}.md").read_text() for name in NAMES}
LIMITS = {"model_requests": 12, "total_tokens": 262144, "tool_calls": 32, "seconds": 125}


def procedure(role: str, fallback: bool = False) -> str:
    names = ["engineering" if role == "implementer" else "review"]
    if fallback:
        names.append("recovery")
    for name in names:
        if files(__package__).joinpath(f"runbooks/{name}.md").read_text() != _CONTENT[name]:
            raise ValueError("Procedure changed after import; restart with a new build")
    return "\n\n".join(_CONTENT[name] for name in names)


def settings() -> dict:
    thinking = PROFILE == "tools-thinking"
    return {
        "temperature": 0.6 if thinking else 0.7,
        "top_p": 0.95 if thinking else 0.8,
        "max_tokens": 16384 if thinking else 8192,
        "parallel_tool_calls": False,
        "tool_choice": "auto",
        "extra_body": {
            "top_k": 20,
            "presence_penalty": 0.0 if thinking else 1.5,
            "chat_template_kwargs": {"enable_thinking": thinking},
        },
    }


def manifest() -> dict:
    return {
        "version": 1,
        "profile": PROFILE,
        "limits": dict(LIMITS),
        "model_settings": settings()
        if PROFILE != "legacy"
        else {"temperature": 0, "enable_thinking": False, "max_tokens": 8192},
        "procedures": {
            name: {"content": text, "sha256": hashlib.sha256(text.encode()).hexdigest()}
            for name, text in _CONTENT.items()
        },
        "package_sources": {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in files(__package__).iterdir()
            if p.name.endswith(".py")
        },
        "promotion": "none; profile selection is not qualification",
    }
