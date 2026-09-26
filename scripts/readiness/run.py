"""Public deterministic controls in a disposable kind cluster, never Kubani.

Only authored images/manifests run here. This is NOT an arbitrary-agent sandbox.
Every kubectl call executes inside the newly created node with its private admin
config; neither the user's kubeconfig nor a production endpoint is consulted.
"""

import argparse
import copy
import hashlib
import io
import json
import os
import re
import subprocess
import tarfile
import time
import uuid
from dataclasses import asdict
from pathlib import Path

from .contract import (
    VERSION,
    Observation,
    digest,
    grade,
    manifest,
    ready_window,
    repair,
    scope_errors,
)
from .tools import FIXTURES, ROOT, TOOLCHAIN, TOOLS, prepare

MACHINE = "starbase2-readiness-lab"
CONNECTION = MACHINE + "-root"
NAMESPACE = "readiness-lab"

# Executed in an observer pod, never in the service under test. Expected answers
# remain in this coordinator. A successful HTTP status alone is insufficient.
PROBE = """
import json, sys, urllib.request, urllib.error
answers=[]
for value in (-3, 0, 7):
    try:
        with urllib.request.urlopen(sys.argv[1]+'/work?value='+str(value), timeout=1) as r:
            answers.append({'status':r.status, 'body':json.loads(r.read(4096))})
    except (OSError, ValueError) as e:
        answers.append({'error':type(e).__name__})
print(json.dumps(answers))
"""


def functional(answers: list) -> bool:
    expected = [
        {"status": 200, "body": {"value": value, "result": expected}}
        for value, expected in ((-3, 10), (0, 1), (7, 50))
    ]
    # Python equality aliases True with 1 and 1.0 with 1. The fixture's job
    # contract requires integer inputs/results, not merely equal Python values.
    return answers == expected and all(
        type(answer["body"][key]) is int for answer in answers for key in ("value", "result")
    )


def fresh(resource: dict) -> bool:
    status, meta = resource.get("status", {}), resource.get("metadata", {})
    generation = meta.get("generation")
    return generation is not None and any(
        c.get("type") == "Ready"
        and c.get("status") == "True"
        and c.get("observedGeneration") == generation
        for c in status.get("conditions", [])
    )


def verify_imported_image(listing: str, reference: str, expected_digest: str) -> None:
    """Check the pinned containerd table before creating a CRI digest alias."""
    rows = [line.split() for line in listing.splitlines()[1:] if line.strip()]
    if (
        len(rows) != 1
        or len(rows[0]) < 3
        or rows[0][0] != reference
        or rows[0][2] != expected_digest
    ):
        raise RuntimeError(
            f"Imported fixture image differs from exported digest {expected_digest}: {rows}"
        )


def archive_digest(path: Path, tag: str, image_id: str) -> str:
    """Bind an OCI export to the built config, allowing transport recompression.

    Podman save may rewrite layer representation and hence the manifest digest.
    Its config (including uncompressed rootfs diff IDs) must remain byte-identical.
    """
    with tarfile.open(path) as archive:

        def read(name: str) -> bytes:
            member = archive.getmember(name)
            if not member.isfile() or member.size > 1_048_576:
                raise RuntimeError("Invalid OCI metadata member")
            stream = archive.extractfile(member)
            assert stream is not None
            return stream.read()

        def blob(reference: str) -> bytes:
            if not re.fullmatch(r"sha256:[a-f0-9]{64}", reference):
                raise RuntimeError("Invalid OCI digest")
            payload = read("blobs/sha256/" + reference.split(":")[1])
            if "sha256:" + hashlib.sha256(payload).hexdigest() != reference:
                raise RuntimeError("OCI metadata checksum mismatch")
            return payload

        index = json.loads(read("index.json"))
        if len(index["manifests"]) != 1:
            raise RuntimeError("Expected one fixture image in OCI export")
        descriptor = index["manifests"][0]
        if descriptor.get("annotations", {}).get("org.opencontainers.image.ref.name") != tag:
            raise RuntimeError("OCI export reference differs from built fixture tag")
        image = json.loads(blob(descriptor["digest"]))
        config = image["config"]["digest"]
        if config.removeprefix("sha256:") != image_id.removeprefix("sha256:"):
            raise RuntimeError("OCI export config differs from built image identity")
        facts = json.loads(blob(config))
        if (facts["os"], facts["architecture"]) != ("linux", "arm64"):
            raise RuntimeError("Fixture export has an unsupported platform")
        return descriptor["digest"]


class Lab:
    def __init__(self, output: Path):
        self.output = output.resolve()
        self.output.mkdir(parents=True, exist_ok=False, mode=0o700)
        self.name = "sb-readiness-" + uuid.uuid4().hex[:10]
        self.node = self.name + "-control-plane"
        self.private = self.output / "private"
        self.private.mkdir(mode=0o700)
        self.repo = self.private / "work"
        self.bare = self.private / "scenario.git"
        self.created = False
        self.sequence = 0
        # No inherited Git config, KUBECONFIG, tokens or provider environment.
        self.env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin:/opt/homebrew/bin"),
            "HOME": str(self.private),
            "LANG": "C.UTF-8",
            "CONTAINER_CONNECTION": CONNECTION,
            "CONTAINERS_CONF": str(self.private / "containers.conf"),
            "KIND_EXPERIMENTAL_PROVIDER": "podman",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Starbase fixture",
            "GIT_AUTHOR_EMAIL": "fixture@invalid",
            "GIT_COMMITTER_NAME": "Starbase fixture",
            "GIT_COMMITTER_EMAIL": "fixture@invalid",
        }
        # Podman locates its macOS VM control sockets under the user's TMPDIR.
        # Keep this IPC location without inheriting provider or Kubernetes settings.
        if "TMPDIR" in os.environ:
            self.env["TMPDIR"] = os.environ["TMPDIR"]
        # Podman connections are selected explicitly using the existing connection
        # file. No registry auth is forwarded to image builds or Kubernetes pods.
        self.env["PODMAN_CONNECTIONS_CONF"] = str(
            Path.home() / ".config/containers/podman-connections.json"
        )
        (self.private / "containers.conf").write_text("[containers]\nlog_driver = 'k8s-file'\n")
        self.images = dict(TOOLCHAIN["images"])
        self.report: dict = {
            "contract": VERSION,
            "mode": "public-deterministic-controls",
            "xp": 0,
            "model_calls": 0,
            "cluster": self.name,
            "toolchain": TOOLCHAIN,
            "source_hashes": {
                str(p.relative_to(ROOT)): digest(p.read_text())
                for directory in (ROOT / "scripts/readiness", FIXTURES)
                for p in sorted(directory.rglob("*"))
                if p.is_file() and "__pycache__" not in p.parts
            },
            "controls": [],
            "cleanup": "pending",
            "status": "running",
        }
        for relative, expected in self.report["source_hashes"].items():
            source = ROOT / relative
            contents = source.read_text()
            if digest(contents) != expected:
                raise RuntimeError("Scenario source changed during preparation")
            target = self.output / "sources" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents)
        self.fixtures = self.output / "sources/fixtures/readiness"
        self.save()

    def save(self):
        path = self.output / "report.json"
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.report, indent=2) + "\n")
        temporary.replace(path)

    def call(self, *args: str, data: bytes | None = None, timeout=60, cwd=None) -> bytes:
        result = subprocess.run(
            args,
            input=data,
            cwd=cwd,
            env=self.env,
            capture_output=True,
            timeout=timeout,
        )
        if result.returncode:
            message = result.stderr.decode(errors="replace")[-4000:]
            raise RuntimeError(f"{args[0]} {args[1:3]} failed ({result.returncode}): {message}")
        return result.stdout

    def podman(self, *args: str, **kwargs) -> bytes:
        return self.call("podman", "--connection", CONNECTION, *args, **kwargs)

    def kubectl(self, *args: str, **kwargs) -> bytes:
        if not self.created:
            raise RuntimeError("No owned disposable node; refusing kubectl dispatch")
        return self.podman(
            "exec",
            "-i",
            self.node,
            "kubectl",
            "--kubeconfig=/etc/kubernetes/admin.conf",
            "--request-timeout=20s",
            *args,
            **kwargs,
        )

    def apply(self, value: dict):
        self.kubectl("apply", "-f", "-", data=json.dumps(value).encode())

    def get(self, resource: str, name: str = "", namespace: str = NAMESPACE) -> dict:
        args = ["get", resource]
        if name:
            args.append(name)
        return json.loads(self.kubectl(*args, "-n", namespace, "-o", "json"))

    def setup(self):
        # Refuse the shared default VM; this machine has its own disk and only an
        # empty lab mount. These are trusted development controls, not an egress sandbox.
        inspected = subprocess.run(
            ["podman", "machine", "inspect", MACHINE],
            check=True,
            capture_output=True,
            timeout=15,
            env={
                "PATH": self.env["PATH"],
                "HOME": str(Path.home()),
                **({"TMPDIR": self.env["TMPDIR"]} if "TMPDIR" in self.env else {}),
            },
        )
        info = json.loads(inspected.stdout)[0]
        machine_config = json.loads(
            (
                Path.home() / ".config/containers/podman/machine/applehv" / (MACHINE + ".json")
            ).read_text()
        )
        mounts = machine_config.get("Mounts")
        empty = ROOT / ".local/readiness-empty"
        if (
            not isinstance(mounts, list)
            or len(mounts) != 1
            or mounts[0].get("Target") != "/lab"
            or mounts[0].get("Source") != str(empty)
            or not empty.is_dir()
            or list(empty.iterdir())
        ):
            raise RuntimeError("Lab VM has unexpected host mounts")
        if info.get("State") != "running":
            raise RuntimeError("Dedicated lab VM is stopped; no shared VM or cluster was touched")
        version = (
            self.podman("version", "--format", "{{.Client.Version}} {{.Server.Version}}")
            .decode()
            .strip()
        )
        if version != (
            TOOLCHAIN["podman_client_version"] + " " + TOOLCHAIN["podman_server_version"]
        ):
            raise RuntimeError("Unpinned Podman version: " + version)
        self.report["podman"] = version
        for name, image in self.images.items():
            print("Pulling pinned " + name, flush=True)
            self.podman("pull", "--authfile", str(self.private / "auth.json"), image, timeout=360)
        for kind in ("service", "git"):
            directory = self.fixtures / kind
            tag = (
                "localhost/sb-readiness-"
                + kind
                + ":"
                + digest(
                    {
                        "files": {
                            p.name: p.read_text()
                            for p in sorted(directory.iterdir())
                            if p.is_file()
                        },
                        "bases": TOOLCHAIN["images"],
                    }
                )[:20]
            )
            self.podman(
                "build",
                "--pull=never",
                "--network=none",
                "--no-cache",
                "--build-arg",
                "PYTHON_IMAGE=" + self.images["python"],
                "--build-arg",
                "GIT_IMAGE=" + self.images["git"],
                "-t",
                tag,
                "-f",
                str(directory / "Containerfile"),
                str(directory),
                timeout=180,
            )
            info = json.loads(self.podman("image", "inspect", tag))[0]
            self.images["built-" + kind] = tag
            self.report[kind + "_image_id"] = info["Id"]
            self.report[kind + "_image_digest"] = info["Digest"]
        config = self.private / "kind.json"
        config.write_text(
            json.dumps(
                {
                    "kind": "Cluster",
                    "apiVersion": "kind.x-k8s.io/v1alpha4",
                    "networking": {"apiServerAddress": "127.0.0.1"},
                    "nodes": [{"role": "control-plane"}],
                }
            )
        )
        self.created = True  # Even a partial creation must be reconciled/removed.
        print("Creating " + self.name, flush=True)
        self.call(
            str(TOOLS / "kind"),
            "create",
            "cluster",
            "--name",
            self.name,
            "--config",
            str(config),
            "--kubeconfig",
            str(self.private / "kubeconfig"),
            "--image",
            self.images["node"],
            "--wait",
            "120s",
            timeout=240,
        )
        for key in ("source", "kustomize", "built-service", "built-git"):
            image = self.images[key]
            archive = self.private / (key + ".tar")
            # Preserve OCI manifest digests across the Podman/containerd transfer.
            self.podman("save", "--format", "oci-archive", "-o", str(archive), image, timeout=120)
            if key.startswith("built-"):
                kind = key.removeprefix("built-")
                self.report[kind + "_export_digest"] = archive_digest(
                    archive, image, self.report[kind + "_image_id"]
                )
            self.call(
                str(TOOLS / "kind"),
                "load",
                "image-archive",
                "--name",
                self.name,
                str(archive),
                timeout=120,
            )
        for kind in ("service", "git"):
            tag = self.images["built-" + kind]
            expected = self.report[kind + "_export_digest"]
            listing = self.podman(
                "exec",
                self.node,
                "ctr",
                "-n",
                "k8s.io",
                "images",
                "ls",
                "name==" + tag,
            ).decode()
            verify_imported_image(listing, tag, expected)
            reference = tag.rsplit(":", 1)[0] + "@" + expected
            self.podman("exec", self.node, "ctr", "-n", "k8s.io", "images", "tag", tag, reference)
            self.images["built-" + kind] = reference
        exported = self.call(
            str(TOOLS / "flux"),
            "install",
            "--components=source-controller,kustomize-controller",
            "--export",
        )
        for tag, key in (
            ("ghcr.io/fluxcd/source-controller:v1.5.0", "source"),
            ("ghcr.io/fluxcd/kustomize-controller:v1.5.1", "kustomize"),
        ):
            exported = exported.replace(tag.encode(), self.images[key].encode())
        (self.output / "flux-install.yaml").write_bytes(exported)
        self.kubectl("apply", "-f", "-", data=exported)
        self.kubectl(
            "wait",
            "deployment",
            "--all",
            "-n",
            "flux-system",
            "--for=condition=Available",
            "--timeout=120s",
            timeout=140,
        )
        self.apply({"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": NAMESPACE}})
        self.bootstrap_pods()
        self.repo.mkdir()
        self.call("git", "init", "-b", "main", str(self.repo))
        self.call("git", "init", "--bare", "-b", "main", str(self.bare))
        self.call("git", "-C", str(self.repo), "remote", "add", "origin", str(self.bare))
        self.report["images"] = self.images
        self.save()

    def bootstrap_pods(self):
        for name, image in (("git", "built-git"), ("observer", "built-service")):
            container = {"name": name, "image": self.images[image], "imagePullPolicy": "Never"}
            spec = {
                "automountServiceAccountToken": False,
                "securityContext": {"runAsUser": 10001, "runAsGroup": 10001, "fsGroup": 10001},
                "containers": [container],
            }
            if name == "git":
                spec["volumes"] = [{"name": "git", "emptyDir": {}}]
                container["volumeMounts"] = [{"name": "git", "mountPath": "/git"}]
            else:
                container["command"] = ["python3", "-c", "import time; time.sleep(3600)"]
            self.apply(
                {
                    "apiVersion": "v1",
                    "kind": "Pod",
                    "metadata": {"name": name, "namespace": NAMESPACE, "labels": {"app": name}},
                    "spec": spec,
                }
            )
        self.apply(
            {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {"name": "git", "namespace": NAMESPACE},
                "spec": {"selector": {"app": "git"}, "ports": [{"port": 8000}]},
            }
        )
        self.kubectl(
            "wait",
            "pod",
            "git",
            "observer",
            "-n",
            NAMESPACE,
            "--for=condition=Ready",
            "--timeout=60s",
            timeout=80,
        )

    def publish(self, deployment: dict, label: str) -> tuple[str, str]:
        deployment = copy.deepcopy(deployment)
        fingerprint = digest(deployment)
        deployment["spec"]["template"]["metadata"]["annotations"] = {
            "lab.starbase2/manifest": fingerprint
        }
        service = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {"name": "worker", "namespace": NAMESPACE},
            "spec": {
                "selector": {"app": "readiness-fixture"},
                "ports": [{"port": 8080, "targetPort": "http"}],
            },
        }
        (self.repo / "resources.json").write_text(
            json.dumps(
                {"apiVersion": "v1", "kind": "List", "items": [deployment, service]}, indent=2
            )
        )
        (self.repo / "kustomization.yaml").write_text("resources:\n  - resources.json\n")
        self.call("git", "-C", str(self.repo), "add", "resources.json", "kustomization.yaml")
        self.call(
            "git",
            "-C",
            str(self.repo),
            "-c",
            "commit.gpgsign=false",
            "commit",
            "--allow-empty",
            "-m",
            label,
        )
        revision = self.call("git", "-C", str(self.repo), "rev-parse", "HEAD").decode().strip()
        self.call("git", "-C", str(self.repo), "push", "origin", "HEAD:main")
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode="w") as bundle:
            bundle.add(self.bare, arcname="scenario.git")
        self.kubectl(
            "exec",
            "-i",
            "git",
            "-n",
            NAMESPACE,
            "--",
            "tar",
            "xf",
            "-",
            "-C",
            "/git",
            data=stream.getvalue(),
        )
        self.apply(
            {
                "apiVersion": "source.toolkit.fluxcd.io/v1",
                "kind": "GitRepository",
                "metadata": {"name": "scenario", "namespace": "flux-system"},
                "spec": {
                    "interval": "2s",
                    "url": "http://git.readiness-lab.svc:8000/scenario.git",
                    "ref": {"branch": "main", "commit": revision},
                },
            }
        )
        self.apply(
            {
                "apiVersion": "kustomize.toolkit.fluxcd.io/v1",
                "kind": "Kustomization",
                "metadata": {"name": "scenario", "namespace": "flux-system"},
                "spec": {
                    "interval": "2s",
                    "timeout": "15s",
                    "prune": True,
                    "wait": False,
                    "path": "./",
                    "sourceRef": {"kind": "GitRepository", "name": "scenario"},
                },
            }
        )
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            obj = self.get("kustomization", "scenario", "flux-system")
            if fresh(obj) and obj["status"].get("lastAppliedRevision", "").endswith(":" + revision):
                return revision, fingerprint
            time.sleep(2)
        raise RuntimeError("Flux did not apply expected revision " + revision)

    def observe(self, revision: str, fingerprint: str, start: float) -> tuple[Observation, dict]:
        deployment = self.get("deployment", "readiness-fixture")
        flux = self.get("kustomization", "scenario", "flux-system")
        source = self.get("gitrepository", "scenario", "flux-system")
        pods = self.get("pods")["items"]
        current = [
            p
            for p in pods
            if p["metadata"].get("annotations", {}).get("lab.starbase2/manifest") == fingerprint
            and not p["metadata"].get("deletionTimestamp")
        ]
        pod = current[0] if len(current) == 1 else {}
        status = deployment.get("status", {})
        ready = all(
            status.get(k) == 1
            for k in ("replicas", "updatedReplicas", "readyReplicas", "availableReplicas")
        )
        answers = {}
        pod_ip = pod.get("status", {}).get("podIP")
        if pod_ip:
            for name, host in (("pod", pod_ip), ("service", "worker.readiness-lab.svc")):
                answers[name] = json.loads(
                    self.kubectl(
                        "exec",
                        "observer",
                        "-n",
                        NAMESPACE,
                        "--",
                        "python3",
                        "-I",
                        "-c",
                        PROBE,
                        "http://" + host + ":8080",
                    )
                )
        applied = flux.get("status", {}).get("lastAppliedRevision", "").split(":")[-1]
        observation = Observation(
            elapsed_seconds=round(time.monotonic() - start, 3),
            revision=applied,
            flux_current=fresh(flux)
            and fresh(source)
            and source.get("status", {})
            .get("artifact", {})
            .get("revision", "")
            .endswith(":" + revision),
            workload_current=status.get("observedGeneration")
            == deployment["metadata"]["generation"]
            and deployment["spec"]["template"]["metadata"]
            .get("annotations", {})
            .get("lab.starbase2/manifest")
            == fingerprint,
            ready=ready,
            pod_uid=pod.get("metadata", {}).get("uid", ""),
            restarts=sum(
                c.get("restartCount", 0) for c in pod.get("status", {}).get("containerStatuses", [])
            ),
            functional=all(functional(answers.get(key, [])) for key in ("pod", "service"))
            if answers
            else None,
        )
        return observation, {
            "observation": asdict(observation),
            "answers": answers,
            "deployment": deployment,
            "pod": pod,
            "flux": flux,
            "source": source,
        }

    def wait_workload(self, fingerprint: str) -> dict:
        """Start the observation budget when the intended process exists.

        Flux can finish while Recreate is still terminating the previous Pod.
        Waiting for Ready here would hide precisely the probe faults under test.
        """
        start = time.monotonic()
        while time.monotonic() - start < 75:
            pods = self.get("pods")["items"]
            current = [
                p
                for p in pods
                if p["metadata"].get("annotations", {}).get("lab.starbase2/manifest") == fingerprint
                and not p["metadata"].get("deletionTimestamp")
                and p.get("status", {}).get("phase") == "Running"
                and any(
                    c.get("name") == "worker" and "running" in c.get("state", {})
                    for c in p.get("status", {}).get("containerStatuses", [])
                )
            ]
            if len(current) == 1:
                return {
                    "pod_uid": current[0]["metadata"]["uid"],
                    "wait_seconds": round(time.monotonic() - start, 3),
                    "pod": current[0],
                }
            time.sleep(1)
        raise RuntimeError("Intended fixture process did not start within the rollout budget")

    def sample(
        self, revision: str, fingerprint: str, seconds: int, want_healthy: bool
    ) -> list[dict]:
        start = time.monotonic()
        samples = []
        while time.monotonic() - start < seconds:
            sample, raw = self.observe(revision, fingerprint, start)
            samples.append(raw)
            tail = [Observation(**item["observation"]) for item in samples[-3:]]
            if want_healthy and ready_window(tail, revision):
                break
            time.sleep(2)
        return samples

    def control(self, case: str, action: str, expected: str, variant: str = ""):
        label = case + ("-" + variant if variant else "-" + action)
        print("Control: " + label, flush=True)
        seed = manifest(case, self.images["built-service"])
        proposed = repair(seed, case) if action == "repair" else copy.deepcopy(seed)
        if variant == "tcp-only":
            proposed["spec"]["template"]["spec"]["containers"][0]["readinessProbe"] = {
                "tcpSocket": {"port": "http"}
            }
        elif variant == "wrong-route":
            proposed["spec"]["template"]["spec"]["containers"][0]["readinessProbe"]["httpGet"][
                "path"
            ] = "/missing"
        elif variant == "timeout-only":
            proposed = copy.deepcopy(seed)
            proposed["spec"]["template"]["spec"]["containers"][0]["readinessProbe"][
                "timeoutSeconds"
            ] = 15
        record = {"id": label, "seed": seed, "proposal": proposed, "expected": expected}
        self.report["controls"].append(record)
        self.save()
        if scope_errors(seed, proposed):
            record["grade"] = grade(seed, proposed, "", [], action)
            record["dispatched"] = False
        else:
            seed_revision, fingerprint = self.publish(seed, label + ": seed")
            record["seed_revision"] = seed_revision
            record["seed_activation"] = self.wait_workload(fingerprint)
            # Fault observation is retained before publishing the repair. Probe
            # readiness faults must coexist with a working direct functional path.
            if action == "repair":
                before = self.sample(seed_revision, fingerprint, 12, False)
                record["before"] = before
                if not any(
                    not s["observation"]["ready"] and functional(s["answers"].get("pod", []))
                    for s in before
                ):
                    raise RuntimeError("Seeded failure was not reproduced: " + label)
                revision, fingerprint = self.publish(proposed, label + ": proposal")
                record["proposal_activation"] = self.wait_workload(fingerprint)
            else:
                revision = seed_revision
            record["revision"] = revision
            samples = self.sample(
                revision, fingerprint, 45, expected in {"verified-repair", "verified-no-change"}
            )
            record["samples"] = samples
            if case == "transient-dependency" and not any(
                s["observation"]["functional"] is False for s in samples
            ):
                raise RuntimeError("Transient refusal was not observed before recovery")
            observations = [Observation(**s["observation"]) for s in samples[-3:]]
            record["grade"] = grade(seed, proposed, revision, observations, action)
            record["dispatched"] = True
            record["events"] = self.get("events")
        record["matches_expected"] = record["grade"]["verdict"] == expected
        self.save()
        if not record["matches_expected"]:
            raise RuntimeError("Control disagreed with its predeclared outcome: " + label)

    def cleanup(self):
        if self.created:
            self.call(
                str(TOOLS / "kind"),
                "delete",
                "cluster",
                "--name",
                self.name,
                "--kubeconfig",
                str(self.private / "kubeconfig"),
                timeout=90,
            )
            remaining = self.podman(
                "ps",
                "-a",
                "--filter",
                "label=io.x-k8s.kind.cluster=" + self.name,
                "--format",
                "{{.Names}}",
            ).strip()
            if remaining:
                raise RuntimeError("Owned cluster containers remain after cleanup")
        self.report["cleanup"] = "verified"
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output", type=Path, help="New evidence directory; existing paths are refused"
    )
    args = parser.parse_args()
    prepare()
    pack = json.loads((FIXTURES / "pack.json").read_text())
    if pack["version"] != VERSION or pack["model_calls"] != 0 or pack["xp"] != 0:
        raise ValueError("Unsupported readiness control pack")
    lab = Lab(args.output)
    lab.report["pack"] = pack
    (lab.private / "auth.json").write_text('{"auths":{}}\n')
    try:
        lab.setup()
        for control in pack["controls"]:
            lab.control(**control)
        lab.report["status"] = "passed"
    except BaseException as error:
        lab.report["status"] = "invalid"
        lab.report["error"] = str(error)
        if lab.created:
            try:
                lab.report["diagnostics"] = {
                    "pods": json.loads(lab.kubectl("get", "pods", "-A", "-o", "json")),
                    "events": json.loads(lab.kubectl("get", "events", "-A", "-o", "json")),
                }
            except Exception as diagnostic_error:
                lab.report["diagnostic_error"] = str(diagnostic_error)
        lab.save()
        raise
    finally:
        try:
            lab.cleanup()
        except Exception as error:
            lab.report["cleanup"] = "failed"
            lab.report["status"] = "invalid"
            lab.report["cleanup_error"] = str(error)
            lab.save()
            raise
    print("All public controls matched; evidence: " + str(lab.output / "report.json"))


if __name__ == "__main__":
    main()
