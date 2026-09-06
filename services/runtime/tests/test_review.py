"""Observable behavior required from the useful local review agent."""

from starbase_runtime.review import scan_sources, snapshot_directory


def test_real_python_findings_and_clean_control(tmp_path):
    (tmp_path / "bad.py").write_text("def run(value):\n    return eval(value)\n")
    snapshot = snapshot_directory(tmp_path)
    report = scan_sources(snapshot, "surveyor-v1")
    assert any(f["code"] == "S307" and f["line"] == 2 for f in report["findings"])
    (tmp_path / "bad.py").write_text("def run(value):\n    return int(value)\n")
    assert scan_sources(snapshot_directory(tmp_path), "surveyor-v1")["findings"] == []


def test_snapshot_never_retains_string_secrets_or_follows_symlinks(tmp_path):
    (tmp_path / "safe.py").write_text('TOKEN = "synthetic-private-value"\n')
    (tmp_path / "escape.py").symlink_to("/etc/passwd")
    snapshot = snapshot_directory(tmp_path)
    assert "synthetic-private-value" not in str(snapshot)
    assert [f["path"] for f in snapshot["files"]] == ["safe.py"]


def test_partial_and_invalid_sources_are_never_clean(tmp_path):
    (tmp_path / "bad.py").write_text("def broken(:\n")
    report = scan_sources(snapshot_directory(tmp_path), "surveyor-v2")
    assert report["errors"]
    for n in range(5):
        (tmp_path / f"file{n}.py").write_text("pass\n")
    snapshot = snapshot_directory(tmp_path, max_files=2)
    assert snapshot["skipped"] and len(snapshot["files"]) <= 2


def test_analysis_ignores_repository_ruff_configuration(tmp_path):
    (tmp_path / "ruff.toml").write_text('lint.ignore = ["S307"]\n')
    (tmp_path / "bad.py").write_text("def run(value):\n    return eval(value)\n")
    report = scan_sources(snapshot_directory(tmp_path), "surveyor-v1")
    assert [f["code"] for f in report["findings"]] == ["S307"]


def test_comment_and_multiline_string_masking_keeps_citation_lines(tmp_path):
    (tmp_path / "bad.py").write_text(
        '"""private\ntext"""\n# private\ndef run(x):\n    return eval(x)\n'
    )
    snapshot = snapshot_directory(tmp_path)
    assert "private" not in snapshot["files"][0]["source"]
    report = scan_sources(snapshot, "surveyor-v1")
    assert report["findings"][0]["line"] == 5
