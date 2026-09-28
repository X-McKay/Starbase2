"""The bounded block-edit protocol preserves original coordinates and scope."""

import pytest
from starbase_runtime import sdlc_pilot as pilot
from test_sdlc_families import contract, sources


def patch(*edits):
    return pilot.BlockPatch(rationale="Authored scope control", edits=list(edits))


@pytest.mark.parametrize("line", [1, 6, 10, 11])
def test_blocks_reject_signature_and_outside_method(line):
    with pytest.raises(ValueError, match="outside"):
        pilot.apply_blocks(
            sources("memory-key"), patch({"line": line, "lines": ["pass"]}), contract("memory-key")
        )


def test_blocks_reject_duplicate_original_line():
    edit = {"line": 7, "lines": ["if memory_key is not None:"]}
    with pytest.raises(ValueError, match="duplicated"):
        pilot.apply_blocks(sources("memory-key"), patch(edit, edit), contract("memory-key"))


@pytest.mark.parametrize("text", ["return 1\nreturn 2", "return 1\rreturn 2"])
def test_blocks_reject_embedded_line_breaks(text):
    with pytest.raises(ValueError):
        patch({"line": 8, "lines": [text]})


@pytest.mark.parametrize("reverse", [False, True])
def test_original_line_coordinates_survive_multiple_expansions(reverse):
    files = sources("memory-key")
    edits = [
        {
            "line": 8,
            "lines": ["value = self.memory.get(agent, {}).get(memory_key)", "return value"],
        },
        {"line": 9, "lines": ["values = self.memory.get(agent, {})", "return dict(values)"]},
    ]
    if reverse:
        edits.reverse()
    result = pilot.apply_blocks(files, patch(*edits), contract("memory-key"))
    assert result[pilot.SOURCE] == files[pilot.SOURCE].replace(
        "            return self.memory.get(agent, {}).get(memory_key)",
        "            value = self.memory.get(agent, {}).get(memory_key)\n            return value",
    ).replace(
        "        return dict(self.memory.get(agent, {}))",
        "        values = self.memory.get(agent, {})\n        return dict(values)",
    )
    assert files == sources("memory-key"), "Original source remains immutable"


def test_nested_relative_indentation_preserves_existing_method_indent():
    files = sources("memory-key")
    result = pilot.apply_blocks(
        files,
        patch(
            {
                "line": 8,
                "lines": [
                    "if agent in self.memory:",
                    "    if memory_key in self.memory[agent]:",
                    "        return self.memory[agent][memory_key]",
                    "return None",
                ],
            }
        ),
        contract("memory-key"),
    )
    assert (
        "            if agent in self.memory:\n"
        "                if memory_key in self.memory[agent]:\n"
        "                    return self.memory[agent][memory_key]\n"
        "            return None" in result[pilot.SOURCE]
    )
    assert result[pilot.SOURCE].endswith("    def unrelated(self):\n        return 42\n")


def test_numbered_symbol_rejects_ambiguous_target():
    files = sources("memory-key")
    files[pilot.SOURCE] += "\ndef get_agent_memory():\n    return None\n"
    with pytest.raises(ValueError, match="identity missing"):
        pilot.numbered_symbol(files, contract("memory-key"))


def test_absolute_block_indent_is_normalized_without_flattening_nested_lines():
    files = sources("memory-key")
    edits = [{"line": 7, "lines": ["        if memory_key is not None:"]}]
    result = pilot.apply_blocks(files, patch(*edits), contract("memory-key"))
    assert result == sources("memory-key", corrected=True)
