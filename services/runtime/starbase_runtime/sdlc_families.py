"""Additional installed algent capabilities. Raw VM observations are graded by Core."""

import ast
import json

from . import sdlc_capabilities, sdlc_sandbox

SETUP = """import json, os, sys, tempfile, logging
from pathlib import Path
work = tempfile.TemporaryDirectory(prefix="algent-family-")
os.chdir(work.name)
for name, contents in SOURCE_FILES.items():
    path = Path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)
sys.path.insert(0, work.name)
cases = []
def record(identity, value):
    if value is None: actual = []
    elif type(value) is int: actual = [value]
    elif isinstance(value, dict): actual = sorted(value.values())
    else: actual = [-999]
    cases.append({"id": identity, "actual": actual})
"""
BODIES = {
    "memory-key": """from src.utils.persistence import SimplePersistence
store = SimplePersistence("memory.sqlite")
store.save_agent_memory("agent", "", 7)
store.save_agent_memory("agent", "named", 9)
store.save_agent_memory("other", "named", 11)
record("memory_empty_key", store.get_agent_memory("agent", ""))
record("memory_named", store.get_agent_memory("agent", "named"))
record("memory_missing", store.get_agent_memory("agent", "absent"))
record("memory_other_agent", store.get_agent_memory("other", "named"))
record("memory_all", store.get_agent_memory("agent"))
store.save_agent_memory("agent", "zero", 0)
record("memory_zero", store.get_agent_memory("agent", "zero"))
""",
    "logging-level": """from src.utils.logging import get_logger
name = "starbase-family-control"
log = get_logger(name, "DEBUG")
record("logging_initial", log.level)
get_logger(name, "INFO")
record("logging_update", log.level)
get_logger(name, "ERROR")
record("logging_error", log.level)
record("logging_handlers", len(log.handlers))
get_logger(name)
record("logging_omitted", log.level)
other = get_logger("unrelated-control", "WARNING")
get_logger(name, "DEBUG")
record("logging_other", other.level)
""",
}
PREFIX = "STARBASE_ALGENT_FAMILY_V1="


def applicable(files: dict, contract: dict) -> bool:
    source = files[contract["editable_paths"][0]]
    functions = [
        n
        for n in ast.walk(ast.parse(source))
        if isinstance(n, ast.FunctionDef) and n.name == contract["editable_symbol"]
    ]
    if len(functions) != 1:
        raise ValueError("Expected capability symbol is unavailable")
    fn = functions[0]
    if contract["opportunity"] == "memory-key":
        return any(
            isinstance(n, ast.If) and isinstance(n.test, ast.Name) and n.test.id == "memory_key"
            for n in ast.walk(fn)
        )
    if contract["opportunity"] == "logging-level":
        # Only report the known pattern: all setLevel calls nested under the
        # handler-creation condition. Unknown syntax is not silently 'healthy'.
        calls = [
            n
            for n in ast.walk(fn)
            if isinstance(n, ast.Call)
            and isinstance(n.func, ast.Attribute)
            and n.func.attr == "setLevel"
        ]
        guards = [
            n
            for n in ast.walk(fn)
            if isinstance(n, ast.If)
            and ast.dump(n.test)
            == (
                "UnaryOp(op=Not(), operand=Attribute(value=Name(id='logger', ctx=Load()), "
                "attr='handlers', ctx=Load()))"
            )
        ]
        return bool(
            calls
            and guards
            and all(any(call in list(ast.walk(g)) for g in guards) for call in calls)
        )
    raise ValueError("No installed family detector")


def program(files: dict, opportunity: str) -> str:
    sdlc_sandbox.program(files)  # Reuse the exact source-size and path boundary.
    return (
        "SOURCE_FILES = "
        + repr(files)
        + "\n"
        + SETUP
        + BODIES[opportunity]
        + f"print({PREFIX!r} + json.dumps({{'cases': cases}}))\n"
    )


async def run(name: str, files: dict, opportunity: str) -> dict:
    result = await sdlc_sandbox._execute(name, program(files, opportunity))
    result["cases"] = []
    if result["exit_code"] == 0:
        result["cases"] = observations(result["stdout"], opportunity)
    return result


def observations(stdout: str, opportunity: str) -> list:
    lines = [line[len(PREFIX) :] for line in stdout.splitlines() if line.startswith(PREFIX)]
    if len(lines) != 1:
        raise ValueError("Missing or duplicate family observation")
    value = json.loads(lines[0])
    contract = sdlc_capabilities.contract_for("x-mckay/algent", opportunity)
    if not isinstance(value, dict) or set(value) != {"cases"}:
        raise ValueError("Invalid family envelope")
    cases = value.get("cases")
    if not isinstance(cases, list) or len(cases) != len(contract["verification"]["case_ids"]):
        raise ValueError("Incomplete family observation")
    for case, identity in zip(cases, contract["verification"]["case_ids"], strict=True):
        if (
            not isinstance(case, dict)
            or set(case) != {"id", "actual"}
            or case["id"] != identity
            or not isinstance(case["actual"], list)
            or len(case["actual"]) > 100
            or any(type(v) is not int for v in case["actual"])
        ):
            raise ValueError("Invalid family observation")
    return cases


def public_artifact(opportunity: str) -> tuple[str, str]:
    # Separately authored reviewable tests; these are not the Core expected values.
    assertions = {
        "memory-key": """from src.utils.persistence import SimplePersistence
s = SimplePersistence("memory.sqlite")
s.save_agent_memory("a", "", 7)
s.save_agent_memory("a", "key", 9)
s.save_agent_memory("b", "key", 11)
assert s.get_agent_memory("a", "") == 7
assert s.get_agent_memory("a", "key") == 9
assert s.get_agent_memory("a", "missing") is None
assert s.get_agent_memory("b", "key") == 11
assert s.get_agent_memory("a") == {"": 7, "key": 9}
s.save_agent_memory("a", "zero", 0)
assert s.get_agent_memory("a", "zero") == 0
""",
        "logging-level": """from src.utils.logging import get_logger
l = get_logger("public-regression", "DEBUG")
assert l.level == 10
get_logger("public-regression", "INFO")
assert l.level == 20
get_logger("public-regression", "ERROR")
assert l.level == 40
assert len(l.handlers) == 1
get_logger("public-regression")
assert l.level == 40
other = get_logger("public-other", "WARNING")
get_logger("public-regression", "DEBUG")
assert other.level == 30
""",
    }
    code = '''"""Trusted narrow regression."""
import os, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
class FamilyRegression(unittest.TestCase):
    def test_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            previous = os.getcwd()
            try:
                os.chdir(directory)
'''
    code += "".join(
        "                " + line + "\n" for line in assertions[opportunity].splitlines()
    )
    code += "            finally:\n                os.chdir(previous)\n"
    return "tests/test_starbase_" + opportunity.replace("-", "_") + ".py", code
