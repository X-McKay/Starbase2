"""Generate or check Rust-owned JSON Schema and the Python wire models."""

import argparse
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def generate(check: bool, version: int) -> None:
    with tempfile.TemporaryDirectory() as directory:
        stage = Path(directory)
        schema = stage / "core.schema.json"
        schema.write_bytes(
            subprocess.check_output(
                [
                    str(ROOT / "target/debug/starbase-core"),
                    "--schema" if version == 1 else f"--schema-v{version}",
                ]
            )
        )
        model = stage / "contract.py"
        subprocess.run(
            [
                str(ROOT / ".venv/bin/datamodel-codegen"),
                "--input",
                str(schema),
                "--input-file-type",
                "jsonschema",
                "--output",
                str(model),
                "--output-model-type",
                "pydantic_v2.BaseModel",
                "--target-python-version",
                "3.12",
                "--disable-timestamp",
                "--use-annotated",
                "--formatters",
                "ruff-format",
            ],
            check=True,
        )
        subprocess.run([str(ROOT / ".venv/bin/ruff"), "check", "--fix", str(model)], check=True)
        subprocess.run([str(ROOT / ".venv/bin/ruff"), "format", str(model)], check=True)
        for source, target in [
            (
                schema,
                ROOT
                / (
                    "contracts/core.schema.json"
                    if version == 1
                    else (
                        "contracts/operations.schema.json"
                        if version == 2
                        else (
                            "contracts/repair.schema.json"
                            if version == 3
                            else "contracts/field.schema.json"
                        )
                    )
                ),
            ),
            (
                model,
                ROOT
                / (
                    "services/runtime/starbase_runtime/contract.py"
                    if version == 1
                    else (
                        "services/runtime/starbase_runtime/operations_contract.py"
                        if version == 2
                        else (
                            "services/runtime/starbase_runtime/repair_contract.py"
                            if version == 3
                            else "services/runtime/starbase_runtime/field_contract.py"
                        )
                    )
                ),
            ),
        ]:
            if check:
                if source.read_bytes() != target.read_bytes():
                    raise SystemExit(f"Generated contract drift: {target}. Run just contracts.")
            else:
                target.write_bytes(source.read_bytes())
    print("Contracts match." if check else "Contracts generated.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for version in (1, 2, 3, 4):
        generate(args.check, version)
