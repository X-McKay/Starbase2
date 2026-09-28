"""Trusted public regression artifact, published only after independent grading.

This test is reviewable PR content, not the candidate VM's grader. The VM harness
and Core expected values remain separately owned.
"""

PATH = "tests/test_persistence_history.py"
SOURCE = '''"""Conversation ordering regression.
Run: python -m unittest discover -s tests -p test_persistence_history.py
"""
import gc
import importlib
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


class ConversationHistoryTests(unittest.TestCase):
    def setUp(self):
        # The module creates a default database at import: keep it disposable too.
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        # SQLite context managers commit but do not close connections.
        # Collect handles left by the legacy implementation between cases.
        self.addCleanup(gc.collect)
        previous = os.getcwd()
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        self.addCleanup(sys.path.pop, 0)
        try:
            os.chdir(self.directory.name)
            module = importlib.import_module("src.utils.persistence")
            self.store = module.SimplePersistence("history.sqlite")
        finally:
            os.chdir(previous)
        self.store.db_path = Path(self.directory.name) / "history.sqlite"
        for index in range(5):
            self.store.add_conversation_history("agent", "ties", {"index": index})
        self.store.add_conversation_history("agent", "other", {"index": 9})
        for index in range(5):
            self.store.add_conversation_history("agent", "mixed", {"index": index})
        with sqlite3.connect(self.store.db_path) as connection:
            connection.execute(
            "UPDATE conversation_history SET timestamp = ?", ("2026-01-01 00:00:00",)
        )
            for index in range(5):
                connection.execute(
                    "UPDATE conversation_history SET timestamp = ? WHERE context_id = ? "
                "AND json_extract(message, '$.index') = ?",
                    ("2026-01-01 00:00:0" + str(index // 2), "mixed", index),
                )

    def values(self, context, limit):
        return [
            row["message"]["index"]
            for row in self.store.get_conversation_history(context, limit)
        ]

    def test_all_tied_messages_keep_insertion_order(self):
        self.assertEqual(self.values("ties", 100), [0, 1, 2, 3, 4])

    def test_limit_selects_latest_three(self):
        self.assertEqual(self.values("ties", 3), [2, 3, 4])

    def test_limit_selects_latest_one(self):
        self.assertEqual(self.values("ties", 1), [4])

    def test_zero_limit(self):
        self.assertEqual(self.values("ties", 0), [])

    def test_empty_context(self):
        self.assertEqual(self.values("absent", 100), [])

    def test_contexts_are_isolated(self):
        self.assertEqual(self.values("other", 100), [9])

    def test_mixed_timestamps_have_stable_ties(self):
        self.assertEqual(self.values("mixed", 100), [0, 1, 2, 3, 4])


if __name__ == "__main__":
    unittest.main()
'''
