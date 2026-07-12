#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("ingest_cliwoc.py")
SPEC = importlib.util.spec_from_file_location("ingest_cliwoc", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CliwocIngestTests(unittest.TestCase):
    def test_core_field_parser(self):
        chars = [" "] * 110
        chars[0:4] = "1778"
        chars[4:6] = " 1"
        chars[6:8] = " 6"
        chars[12:17] = " 4892"
        chars[17:23] = " 35297"
        chars[34:43] = "       55"
        chars[43:45] = "NL"
        chars[46:49] = " 91"
        chars[50:53] = " 26"
        record = MODULE.parse_core("".join(chars))
        self.assertEqual(record["year"], 1778)
        self.assertAlmostEqual(record["lat"], 48.92)
        self.assertAlmostEqual(record["lon"], -7.03)
        self.assertAlmostEqual(record["wind_speed_mps"], 2.6)
        self.assertEqual(record["wind_direction_deg"], 91.0)

    def test_relative_angle_and_bins_close_at_180(self):
        self.assertEqual(MODULE.relative_wind_angle(350.0, 10.0), 20.0)
        self.assertEqual(MODULE.bin_index(180.0, MODULE.ANGLE_EDGES), 11)
        self.assertIsNone(MODULE.bin_index(51.0, MODULE.SPEED_EDGES))

    def test_route_assignment_is_single_and_bounded(self):
        self.assertIn(MODULE.nearest_leg(-15.965, -5.708, 900.0), (0, 1))
        self.assertIn(MODULE.nearest_leg(-33.9, 18.42, 900.0), (1, 2))
        self.assertIsNone(MODULE.nearest_leg(75.0, -150.0, 900.0))


if __name__ == "__main__":
    unittest.main()
