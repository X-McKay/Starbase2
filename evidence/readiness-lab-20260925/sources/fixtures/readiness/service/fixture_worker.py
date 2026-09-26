"""Synthetic job package installed ONLY in the worker's virtual environment."""

import os
import urllib.request


def work(value: int) -> int:
    return value * value + 1


def check(path: str) -> None:
    port = os.environ.get("HTTP_PORT", "8080")
    with urllib.request.urlopen("http://127.0.0.1:" + port + path, timeout=0.5) as response:
        assert response.status == 200
