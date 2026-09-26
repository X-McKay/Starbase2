"""Real credential-free fixture processes; no Kubernetes, models, or containers."""

import contextlib
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

import pytest

from scripts.readiness.tools import FIXTURES


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@pytest.fixture(scope="module")
def worker_python(tmp_path_factory):
    target = tmp_path_factory.mktemp("readiness-worker") / "venv"
    subprocess.run(
        [sys.executable, "-m", "venv", "--without-pip", str(target)], check=True, timeout=30
    )
    python = str(target / "bin/python3")
    package = target / "lib/python3.12/site-packages/fixture_worker.py"
    shutil.copyfile(FIXTURES / "service/fixture_worker.py", package)
    return python


@contextlib.contextmanager
def service(python, *, delay="0", broken="False"):
    port = free_port()
    dependency_port = free_port()
    while dependency_port == port:
        dependency_port = free_port()
    env = {
        "PATH": "/usr/bin:/bin",
        "PYTHONDONTWRITEBYTECODE": "1",
        "HTTP_PORT": str(port),
        "DEPENDENCY_PORT": str(dependency_port),
        "BIND_ADDRESS": "127.0.0.1",
        "DEPENDENCY_DELAY": delay,
        "BROKEN_WORK": broken,
    }
    process = subprocess.Popen(
        [python, "-I", "-B", str(FIXTURES / "service/server.py")],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    base = "http://127.0.0.1:" + str(port)
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise AssertionError(process.communicate()[1].decode())
            try:
                with urllib.request.urlopen(base + "/live", timeout=0.2):
                    break
            except OSError:
                time.sleep(0.02)
        else:
            raise AssertionError("Fixture did not listen")
        yield base, env
    finally:
        process.terminate()
        process.communicate(timeout=5)


def request(base, path):
    try:
        with urllib.request.urlopen(base + path, timeout=1) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def test_missing_health_route_coexists_with_functional_worker(worker_python):
    with service(worker_python) as (base, env):
        assert request(base, "/health")[0] == 404
        assert request(base, "/ready")[0] == 200
        assert request(base, "/work?value=-3") == (200, {"value": -3, "result": 10})
        code = "from fixture_worker import check; check('/ready')"
        wrong = subprocess.run(
            [sys.executable, "-I", "-c", code], env=env, capture_output=True, timeout=5
        )
        assert wrong.returncode != 0 and b"ModuleNotFoundError" in wrong.stderr
        correct = subprocess.run(
            [worker_python, "-I", "-c", code], env=env, capture_output=True, timeout=5
        )
        assert correct.returncode == 0, correct.stderr.decode()


def test_transient_dependency_recovers_without_a_restart(worker_python):
    with service(worker_python, delay="1") as (base, _):
        assert request(base, "/ready") == (503, {"error": "dependency-connection-refused"})
        assert request(base, "/live")[0] == 200
        deadline = time.monotonic() + 3
        while request(base, "/ready")[0] == 503 and time.monotonic() < deadline:
            time.sleep(0.05)
        assert request(base, "/work?value=7") == (200, {"value": 7, "result": 50})


def test_persistent_and_false_ready_controls(worker_python):
    with service(worker_python, delay="-1") as (base, _):
        assert request(base, "/work?value=0")[0] == 503
        assert request(base, "/ready")[0] == 503
        assert request(base, "/live")[0] == 200
    with service(worker_python, broken="True") as (base, _):
        assert request(base, "/ready")[0] == 200
        assert request(base, "/work?value=0") == (200, {"value": 0, "result": 2})


def test_commands_cannot_use_ambient_cluster_or_provider_environment(tmp_path, monkeypatch):
    from scripts.readiness.run import CONNECTION, Lab

    monkeypatch.setenv("KUBECONFIG", "/production/config")
    monkeypatch.setenv("OPENAI_API_KEY", "test-only-value")
    lab = Lab(tmp_path / "run")
    assert "KUBECONFIG" not in lab.env and "OPENAI_API_KEY" not in lab.env
    assert lab.env["HOME"] != os.environ["HOME"]
    with pytest.raises(RuntimeError, match="No owned disposable node"):
        lab.kubectl("get", "pods")
    lab.created = True
    calls = []
    monkeypatch.setattr(lab, "call", lambda *args, **kwargs: calls.append(args) or b"{}")
    lab.kubectl("get", "pods")
    assert calls[0][:6] == ("podman", "--connection", CONNECTION, "exec", "-i", lab.node)
    assert "--kubeconfig=/etc/kubernetes/admin.conf" in calls[0]


def test_git_transport_serves_exact_commit_and_refuses_publication(tmp_path):
    repository = tmp_path / "repository"
    env = {
        "PATH": "/usr/bin:/bin:/opt/homebrew/bin",
        "HOME": str(tmp_path),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_AUTHOR_NAME": "Fixture",
        "GIT_AUTHOR_EMAIL": "fixture@invalid",
        "GIT_COMMITTER_NAME": "Fixture",
        "GIT_COMMITTER_EMAIL": "fixture@invalid",
    }

    def git(*args):
        return subprocess.run(
            ["git", *args], env=env, check=True, capture_output=True, timeout=10
        ).stdout

    git("init", "-b", "main", str(repository))
    (repository / "resource.json").write_text('{"synthetic":true}')
    git("-C", str(repository), "add", "resource.json")
    git("-C", str(repository), "-c", "commit.gpgsign=false", "commit", "-m", "fixture")
    expected = git("-C", str(repository), "rev-parse", "HEAD")
    bare = tmp_path / "fixture.git"
    git("clone", "--bare", str(repository), str(bare))
    port = free_port()
    env.update(
        {"HTTP_PORT": str(port), "BIND_ADDRESS": "127.0.0.1", "FIXTURE_REPOSITORY": str(bare)}
    )
    process = subprocess.Popen(
        [sys.executable, "-I", str(FIXTURES / "git/server.py")], env=env, stderr=subprocess.PIPE
    )
    base = "http://127.0.0.1:" + str(port)
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(
                    base + "/scenario.git/info/refs?service=git-upload-pack", timeout=0.2
                ):
                    break
            except OSError:
                time.sleep(0.02)
        git("clone", base + "/scenario.git", str(tmp_path / "clone"))
        assert git("-C", str(tmp_path / "clone"), "rev-parse", "HEAD") == expected
        request = urllib.request.Request(base + "/scenario.git/git-receive-pack", data=b"no writes")
        with pytest.raises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request, timeout=1)
        assert error.value.code == 403
    finally:
        process.terminate()
        process.communicate(timeout=5)
