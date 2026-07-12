#!/usr/bin/env python3

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("validate_log_ledger.py")
SPEC = importlib.util.spec_from_file_location("validate_log_ledger", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class LedgerValidationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = Path(__file__).parents[1] / "missions/mercury-1778-outbound-v0/log/route-anchors.v0.json"

    def test_catalogue_anchor_ledger(self):
        report = MODULE.validate(self.fixture)
        self.assertEqual(report["records"], 5)
        self.assertEqual(report["transcription_records"], 0)

    def test_duplicate_and_false_transcription_rejected(self):
        data = json.loads(self.fixture.read_text())
        data["records"][1]["record_id"] = data["records"][0]["record_id"]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "duplicate"):
                MODULE.validate(path)

        data = json.loads(self.fixture.read_text())
        data["records"][0]["raw_text"] = "invented"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "impersonate"):
                MODULE.validate(path)


if __name__ == "__main__":
    unittest.main()
