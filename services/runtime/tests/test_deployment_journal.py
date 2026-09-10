import io
import json
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from scripts.deployment import cli, journal


class HttpFixture:
    def __init__(self):
        self.origin = journal.ORIGIN
        self.identity = "starbase2-test"
        self.field = {
            "id": "observe",
            "agent": "watchkeeper",
            "target": "cluster",
            "enabled": True,
            "inference": True,
            "generation": 4,
            "interval_seconds": 300,
        }
        self.repository = {
            "repository": "owner/repo",
            "enabled": True,
            "removed": False,
            "generation": 2,
            "interval_seconds": 900,
        }
        self.writes = []
        self.active = True
        self.fail_write = False
        self.reenable = False

    def open(self, request, timeout):
        path = (
            request.removeprefix(self.origin)
            if isinstance(request, str)
            else request.full_url.removeprefix(self.origin)
        )
        body = (
            None if isinstance(request, str) or request.data is None else json.loads(request.data)
        )
        if body is not None:
            self.writes.append((path, body))
            if self.fail_write:
                raise TimeoutError("uncertain HTTP write")
            if path == "/v4/duties":
                self.field = body
            elif path == "/v4/repositories":
                self.repository = body
            return io.BytesIO(json.dumps(body).encode())
        if path == "":
            result = {}
        elif path == "/v2/snapshot":
            result = {"duties": [], "installation": {"id": self.identity}}
        elif path == "/v2/runs?active=true":
            result = {"runs": []}
        elif path == "/v3/repairs":
            result = {"repairs": []}
        elif path == "/v4/snapshot":
            field = self.field | ({"enabled": True} if self.reenable else {})
            result = {
                "duties": [field, {"id": "repo-synthetic", "enabled": self.repository["enabled"]}],
                "repositories": [{"config": self.repository}],
                "runs": [{"state": "running" if self.active else "completed"}],
            }
        else:
            raise AssertionError(path)
        return io.BytesIO(json.dumps(result).encode())


def test_drain_pauses_field_and_repository_preserving_authority_then_waits():
    fixture = HttpFixture()

    def finish(_seconds):
        fixture.active = False

    with (
        patch.object(journal.urllib.request, "build_opener", return_value=fixture),
        patch.object(journal.time, "sleep", side_effect=finish) as sleep,
    ):
        result = journal.drain("starbase2-test")
    assert result["drained"]
    assert sleep.call_count == 1
    assert fixture.writes == [
        ("/v4/duties", fixture.field | {"enabled": False, "inference": True, "generation": 5}),
        (
            "/v4/repositories",
            fixture.repository | {"enabled": False, "removed": False, "generation": 3},
        ),
    ]


@pytest.mark.parametrize("reenable", [False, True])
def test_drain_never_succeeds_with_active_field_work_or_reenabled_duty(reenable):
    fixture = HttpFixture()
    fixture.reenable = reenable
    fixture.active = not reenable
    with patch.object(journal.urllib.request, "build_opener", return_value=fixture):
        with pytest.raises(RuntimeError, match="Drain timed out"):
            journal.drain("starbase2-test", timeout=0)


def test_uncertain_pause_is_not_retried():
    fixture = HttpFixture()
    fixture.fail_write = True
    with patch.object(journal.urllib.request, "build_opener", return_value=fixture):
        with pytest.raises(TimeoutError, match="uncertain"):
            journal.drain("starbase2-test")
    assert len(fixture.writes) == 1


def test_already_paused_duties_and_removed_repositories_are_not_rewritten():
    fixture = HttpFixture()
    fixture.field["enabled"] = False
    fixture.repository.update(enabled=False, removed=True)
    fixture.active = False
    with patch.object(journal.urllib.request, "build_opener", return_value=fixture):
        assert journal.drain("starbase2-test")["drained"]
    assert fixture.writes == []


@pytest.mark.parametrize("identity", ["starbase2-other", None])
def test_wrong_installation_never_dispatches_pause(identity):
    fixture = HttpFixture()
    fixture.identity = identity
    with patch.object(journal.urllib.request, "build_opener", return_value=fixture):
        with pytest.raises(ValueError, match="identity mismatch"):
            journal.drain("starbase2-test")
    assert fixture.writes == []


def test_explicit_forward_routes_all_requests_to_selected_port():
    fixture = HttpFixture()
    fixture.origin = "http://127.0.0.1:18787"
    fixture.active = False
    with patch.object(journal.urllib.request, "build_opener", return_value=fixture):
        assert journal.drain("starbase2-test", fixture.origin)["drained"]
    assert len(fixture.writes) == 2


@pytest.mark.parametrize(
    "origin",
    [
        "https://remote.example",
        "http://localhost:8787",
        "http://127.0.0.1:08787",
        "http://127.0.0.1:8787/",
        "http://127.0.0.1:65536",
    ],
)
def test_noncanonical_origin_rejected_before_http(origin):
    with patch.object(journal.urllib.request, "build_opener") as opener:
        with pytest.raises(ValueError, match="canonical"):
            journal.drain("starbase2-test", origin)
    opener.assert_not_called()


def test_cli_binds_config_identity_and_explicit_core_forward():
    argv = [
        "deploy",
        "drain",
        "--config",
        "fixture.json",
        "--execute",
        "--confirm",
        "starbase2-test",
        "--core-address",
        "http://127.0.0.1:18787",
    ]
    with (
        patch.object(sys, "argv", argv),
        patch.object(cli.render, "load", return_value={"installation": "starbase2-test"}),
        patch.object(cli, "ownership"),
        patch.object(journal, "drain", return_value={"drained": True}) as drain,
    ):
        cli.main()
    drain.assert_called_once_with("starbase2-test", "http://127.0.0.1:18787")
