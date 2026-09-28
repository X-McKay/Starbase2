"""Local supervisor safety checks; no service or provider is started."""

import importlib.util
import json
import os
import socket
import sqlite3
from pathlib import Path
from unittest.mock import Mock

import pytest

SPEC = importlib.util.spec_from_file_location(
    "github_monitor", Path(__file__).resolve().parents[3] / "scripts/github_monitor.py"
)
assert SPEC is not None and SPEC.loader is not None
monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(monitor)


def test_identity_rejects_reused_pid():
    record = monitor.identity(os.getpid())
    assert monitor.owned(record)
    assert not monitor.owned(record | {"identity": "a previous process"})
    assert not monitor.owned({"pid": 1, "identity": "anything"})


def test_environment_is_narrow_and_isolates_queue(monkeypatch, tmp_path):
    monkeypatch.setattr(monitor, "LOCAL", tmp_path)
    monkeypatch.setenv("GITHUB_TOKEN", "must-not-inherit")
    monkeypatch.setenv("STARBASE_JOINT_ENABLED", "true")
    monkeypatch.setenv("PYTHONPATH", "/explicit/runtime/path")
    env = monitor.environment("x-mckay")
    assert "GITHUB_TOKEN" not in env
    assert env["STARBASE_TEMPORAL"] == "127.0.0.1:7244"
    assert env["STARBASE_TEMPORAL_QUEUE"] == "starbase2-github-monitor-v1"
    assert env["STARBASE_FIELD_ENABLED"] == "true"
    assert env["PYTHONPATH"].endswith("/explicit/runtime/path")
    for feature in ("LEGACY", "REPAIRS", "JOINT", "LEARNING", "INFERENCE", "MEMORY"):
        assert env[f"STARBASE_{feature}_ENABLED"] == "false"


def test_occupied_port_fails_closed():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        with pytest.raises(RuntimeError, match="occupied"):
            monitor.available(listener.getsockname()[1])


def test_recently_closed_connection_allows_restart():
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        listener.listen()
        with socket.create_connection(("127.0.0.1", port)) as client:
            connection, _ = listener.accept()
            connection.close()
            assert client.recv(1) == b""
    monitor.available(port)


def test_stop_never_signals_unverified_process(monkeypatch):
    record = monitor.identity(os.getpid())
    monkeypatch.setattr(monitor, "read_state", lambda: {"supervisor": record, "nonce": "other"})
    kill = Mock()
    monkeypatch.setattr(monitor.os, "kill", kill)
    with pytest.raises(RuntimeError, match="No verified owned"):
        monitor.stop_monitor()
    kill.assert_not_called()


def test_status_does_not_query_unowned_core(monkeypatch):
    monkeypatch.setattr(monitor, "read_state", lambda: {})
    request = Mock()
    monkeypatch.setattr(monitor.urllib.request, "urlopen", request)
    assert monitor.status()["supervisor"]["alive"] is False
    request.assert_not_called()


def test_backup_is_consistent_and_state_atomic(tmp_path, monkeypatch):
    local = tmp_path / ".local/github-monitor"
    local.mkdir(parents=True)
    monkeypatch.setattr(monitor, "ROOT", tmp_path)
    monkeypatch.setattr(monitor, "LOCAL", local)
    monkeypatch.setattr(monitor, "STATE", local / "processes.json")
    with sqlite3.connect(tmp_path / ".local/starbase.sqlite") as db:
        db.execute("create table preserved (id integer)")
        db.execute("insert into preserved values (42)")
    monitor.backup()
    with sqlite3.connect(next(local.glob("core-before-start-*.sqlite"))) as db:
        assert db.execute("select id from preserved").fetchone() == (42,)
    monitor.write_state({"phase": "testing"})
    assert json.loads(monitor.STATE.read_text()) == {"phase": "testing"}
    assert monitor.STATE.stat().st_mode & 0o777 == 0o600


def test_verification_requires_explicit_local_opt_in(monkeypatch, tmp_path):
    monkeypatch.setattr(monitor, "LOCAL", tmp_path)
    (tmp_path / "sdlc.json").write_text("{}")
    assert "STARBASE_SDLC_VERIFICATION_ENABLED" not in monitor.environment("x-mckay")
    config = tmp_path / "verification.json"
    config.write_text(json.dumps({"repository": "x-mckay/algent", "enabled": True}))
    assert monitor.environment("x-mckay")["STARBASE_SDLC_VERIFICATION_ENABLED"] == "true"
    config.write_text(json.dumps({"repository": "other/repo", "enabled": True}))
    with pytest.raises(ValueError, match="verification opt-in"):
        monitor.environment("x-mckay")


def test_restart_policy_is_finite_and_stop_interrupts_backoff(monkeypatch):
    assert monitor.RESTART_DELAYS == (2, 4, 8)
    asleep = Mock()
    monkeypatch.setattr(monitor.time, "sleep", asleep)
    assert not monitor.wait_for_restart(8, lambda: True)
    asleep.assert_not_called()


@pytest.fixture
def supervisor_harness(monkeypatch, tmp_path):
    import copy
    from types import SimpleNamespace

    harness = SimpleNamespace(
        children=[], states=[], signals={}, now=0.0, on_sleep=lambda: None,
        crash_workers=True, port_calls=0,
    )
    monkeypatch.setattr(monitor, "LOCAL", tmp_path)
    monkeypatch.setattr(monitor, "validate", lambda: "x-mckay")
    monkeypatch.setattr(monitor, "backup", lambda: None)
    monkeypatch.setattr(monitor, "environment", lambda _: {})
    monkeypatch.setattr(monitor, "identity", lambda pid: {"pid": pid, "identity": "owned"})
    monkeypatch.setattr(
        monitor, "write_state", lambda state: harness.states.append(copy.deepcopy(state))
    )
    monkeypatch.setattr(monitor.signal, "signal", lambda sig, fn: harness.signals.update({sig: fn}))
    monkeypatch.setattr(monitor, "service_health", lambda: True)
    monkeypatch.setattr(monitor.time, "monotonic", lambda: harness.now)

    def sleep(seconds):
        harness.now += seconds
        harness.on_sleep()

    def available(_):
        harness.port_calls += 1

    def process(command, **_kwargs):
        child = Mock()
        child.pid = 100 + len(harness.children)
        child.command = command
        child.exited = harness.crash_workers and command[-1] == "worker"
        child.poll.side_effect = lambda: 1 if child.exited else None
        child.terminate.side_effect = lambda: setattr(child, "exited", True)
        harness.children.append(child)
        return child

    monkeypatch.setattr(monitor.time, "sleep", sleep)
    monkeypatch.setattr(monitor, "available", available)
    monkeypatch.setattr(monitor.subprocess, "Popen", process)
    return harness


def test_crash_recovery_exhausts_budget_and_stops_owned_dependencies(supervisor_harness):
    h = supervisor_harness
    monitor.supervise("test")
    final = h.states[-1]
    assert final["phase"] == "failed"
    assert final["recovery"]["restarts"] == 3
    assert len(final["recovery"]["events"]) == 4
    assert final["children"] == {}
    assert len(h.children) == 12  # Initial generation plus exactly three retries.
    assert h.now == pytest.approx(14)
    for child in h.children:
        if child.command[-1] != "worker":
            child.terminate.assert_called_once()
        else:
            child.terminate.assert_not_called()  # Already reaped: do not signal its PID.
    assert h.port_calls == 10  # Initial guard and every generation.


def test_explicit_stop_during_backoff_prevents_restart(supervisor_harness):
    h = supervisor_harness
    h.on_sleep = lambda: h.signals[monitor.signal.SIGTERM](None, None)
    monitor.supervise("test")
    assert len(h.children) == 3
    assert h.states[-1]["phase"] == "stopped"
    assert h.states[-1]["recovery"]["restarts"] == 0


def test_crashed_worker_recovers_then_explicit_stop(supervisor_harness):
    h = supervisor_harness

    def after_sleep():
        h.crash_workers = False
        if len(h.children) == 6:
            h.signals[monitor.signal.SIGTERM](None, None)

    h.on_sleep = after_sleep
    monitor.supervise("test")
    assert len(h.children) == 6
    assert h.states[-1]["phase"] == "stopped"
    assert h.states[-1]["recovery"]["restarts"] == 1
    assert sum(state["phase"] == "recovering" for state in h.states) == 1
    assert all(child.exited for child in h.children)


def test_repeated_health_failure_restarts_while_single_failure_recovers(
    supervisor_harness, monkeypatch,
):
    h = supervisor_harness
    h.crash_workers = False
    health = iter((True, False, True, False, False, False, True))
    monkeypatch.setattr(monitor, "service_health", lambda: next(health))

    def after_sleep():
        if len(h.children) == 6:
            h.signals[monitor.signal.SIGTERM](None, None)

    h.on_sleep = after_sleep
    monitor.supervise("test")
    assert h.states[-1]["recovery"]["restarts"] == 1
    assert h.states[-1]["recovery"]["events"][0]["reason"] == (
        "Monitor transport health repeatedly unavailable"
    )
    assert any(state.get("health", {}).get("consecutive_failures") == 2 for state in h.states)
    assert len(h.children) == 6


def test_recovery_does_not_take_over_newly_occupied_port(supervisor_harness, monkeypatch):
    h = supervisor_harness
    calls = 0

    def available(_):
        nonlocal calls
        calls += 1
        if calls > 4:
            raise RuntimeError("Port occupied; no existing process was stopped")

    monkeypatch.setattr(monitor, "available", available)
    monitor.supervise("test")
    assert len(h.children) == 3
    assert h.states[-1]["phase"] == "failed"
    assert "Port occupied" in h.states[-1]["recovery"]["events"][-1]["reason"]


def test_startup_health_timeout_never_dispatches_worker(supervisor_harness, monkeypatch):
    h = supervisor_harness
    h.crash_workers = False
    monkeypatch.setattr(monitor, "service_health", lambda: False)
    monitor.supervise("test")
    assert len(h.children) == 8  # Four attempts, each only Core and Temporal.
    assert all(child.command[-1] != "worker" for child in h.children)
    assert h.states[-1]["phase"] == "failed"
    assert len(h.states[-1]["recovery"]["events"]) == 4
    assert all(child.exited for child in h.children)
