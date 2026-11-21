#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Independently authored literal grammar/admission fixtures, no game data."""
from pathlib import Path
import sys,unittest

ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tools.assets.prepare_traffic_occupants import parse_tables,TableError

class TrafficTables(unittest.TestCase):
    source='let xs=[5,6,5],xc={400:8,402:0};const bz=new Set([401,403]);'
    def test_authored_literal_tables(self):
        self.assertEqual(parse_tables(self.source),dict(schema=1,fallback=[5,6,5],overrides={'400':8,'402':0},hiddenModels=[401,403]))
    def test_no_evaluation_or_expressions(self):
        for text in [self.source.replace('[5,6,5]','[5,Math.random(),5]'),self.source.replace('400:8','400:run()'),self.source.replace('Set([401,403])','Set(getModels())')]:
            with self.assertRaises(TableError):parse_tables(text)
    def test_ambiguous_literal_rejected(self):
        with self.assertRaises(TableError):parse_tables(self.source+'let xs=[9];')
    def test_boundaries_and_duplicates(self):
        for text in [self.source.replace('400:8,402:0','400:8,400:9'),self.source.replace('[401,403]','[401,401]'),self.source.replace('400:8','65536:8'),self.source.replace('[5,6,5]','[65536]')]:
            with self.assertRaises(TableError):parse_tables(text)
    def test_similar_binding_is_not_selected(self):
        self.assertEqual(parse_tables('let other_xs=[99];'+self.source)['fallback'],[5,6,5])
if __name__=='__main__':unittest.main()
