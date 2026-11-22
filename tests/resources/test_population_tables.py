#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored population resources; no original tables are embedded here."""
from pathlib import Path
import json
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.assets.original_population import cycle_row, parse_cycle, parse_groups, parse_zones, resolve_groups
from tools.assets.prepare_population_tables import prepare


def cycle():
    # Independent address oracle: each source row carries its zone/week/hour.
    return '\n'.join(' '.join(map(str, [zone, part, slot, 180, 0, 255] + [80] + [0] * 17))
                     for zone in range(20) for part in range(2) for slot in range(12))


def groups(count, row='alpha, ALPHA, beta'):
    return '# authored fixture\n' + ('\n' + row + ' # note') * count


ZONE = 'zone\nSYNTH, 0, -2.5, -3, -4, 5, 6, 7, 1, SYNTH\nend\n'


class PopulationTables(unittest.TestCase):
    def test_cycle_all_addresses_and_boundaries(self):
        rows = parse_cycle('// header\n' + cycle())
        for zone in range(20):
            for part in range(2):
                for hour in range(24):
                    self.assertEqual(cycle_row(rows, zone, part, hour)[:3], (zone, part, hour // 2))
                    self.assertEqual(cycle_row(rows, zone, part, hour + .999)[:3], (zone, part, hour // 2))
        self.assertEqual(cycle_row(rows, 19, 1, 23.999)[3:6], (180, 0, 255))

    def test_cycle_keeps_unscaled_group_weights(self):
        rows = parse_cycle(cycle())
        self.assertEqual(sum(rows[0][6:]), 80)
        source = cycle().splitlines(); first = source[0].split(); first[6] = '180'; source[0] = ' '.join(first)
        changed = parse_cycle('\n'.join(source))
        self.assertEqual(sum(cycle_row(changed, 0, 0, 0)[6:]), 180)

    def test_cycle_refuses_malformed_shapes_and_numbers(self):
        valid = cycle().splitlines()
        bad_rows = [' '.join(['0'] * 23), ' '.join(['0'] * 25),
                    '-1 ' + '0 ' * 23, '256 ' + '0 ' * 23,
                    '1.0 ' + '0 ' * 23, 'nan ' + '0 ' * 23]
        for row in bad_rows:
            with self.subTest(row=row), self.assertRaises(ValueError):
                parse_cycle('\n'.join([row] + valid[1:]))
        for rows in [valid[:-1], valid + [valid[0]]]:
            with self.assertRaises(ValueError): parse_cycle('\n'.join(rows))

    def test_cycle_rejects_invalid_addresses(self):
        rows = parse_cycle(cycle())
        for address in [(-1, 0, 0), (20, 0, 0), (True, 0, 0), (0, True, 0),
                        (0, 2, 0), (0, 0, -1), (0, 0, 24), (0, 0, True),
                        (0, 0, float('inf')), (0, 0, float('nan'))]:
            with self.subTest(address=address), self.assertRaises(ValueError): cycle_row(rows, *address)

    def test_groups_preserve_duplicates_and_row_order(self):
        p = parse_groups(groups(57), 'pedestrian')
        v = parse_groups(groups(34), 'vehicle')
        self.assertEqual(p[0], ('alpha', 'alpha', 'beta'))
        self.assertEqual(len(p), 57); self.assertEqual(len(v), 34)

    def test_resolution_looks_up_before_engine_capacity(self):
        names = ['missing'] * 5 + ['m' + str(n) for n in range(30)]
        for kind, count, first, capacity in [('pedestrian', 57, 1, 21), ('vehicle', 34, 400, 23)]:
            rows = parse_groups(groups(count, ','.join(names)), kind)
            mapping = {'m' + str(n): first + n for n in range(30)}
            resolved = resolve_groups(rows, mapping, kind)
            self.assertEqual(resolved[0], tuple(range(first, first + capacity)))
            self.assertEqual(len(resolved), count)

    def test_empty_resolution_never_shifts_row_identity(self):
        rows = list(parse_groups(groups(57), 'pedestrian')); rows[0] = ('unknown',)
        resolved = resolve_groups(rows, {'alpha': 7, 'beta': 8}, 'pedestrian')
        self.assertEqual(resolved[0], ()); self.assertEqual(resolved[1], (7, 7, 8))

    def test_resolution_rejects_wrong_or_ambiguous_identities(self):
        rows = parse_groups(groups(57), 'pedestrian')
        for mapping in [{'alpha': 0}, {'alpha': True}, {'alpha': 400},
                        {'alpha': 7, 'ALPHA': 8}, {'../alpha': 7}]:
            with self.assertRaises(ValueError): resolve_groups(rows, mapping, 'pedestrian')

    def test_groups_refuse_corrupt_tables(self):
        for text in [groups(56), groups(58), groups(57, '../asset'), groups(57, 'bad-name'), groups(57) + '\0']:
            with self.assertRaises(ValueError): parse_groups(text, 'pedestrian')
        with self.assertRaises(ValueError): parse_groups(groups(57), 'invented')

    def test_zones_keep_raw_geometry_and_labels(self):
        zone = parse_zones(ZONE)[0]
        self.assertEqual(zone['minimum'], (-2.5, -3, -4))
        self.assertEqual(zone['maximum'], (5, 6, 7))
        self.assertEqual(zone['label'], 'SYNTH')
        self.assertNotIn('populationType', zone)

    def test_zones_refuse_bad_sections_bounds_and_numbers(self):
        for text in [ZONE.replace('end', ''), ZONE + ZONE, ZONE.replace('-2.5', 'nan'),
                     ZONE.replace('-2.5', '99'), ZONE.replace('SYNTH, 0', 'TOOLONGNAME, 0'),
                     ZONE.replace(', 0,', ', 4,'), 'zone\nend']:
            with self.assertRaises(ValueError): parse_zones(text)

    def test_text_budget_and_null_boundaries(self):
        for value in ['\0', 'x' * (1024 * 1024 + 1), None]:
            with self.assertRaises(ValueError): parse_cycle(value)

    def test_preparation_reuse_refusal_and_source_preservation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); data = root / 'game/DATA'; data.mkdir(parents=True)
            sources = {'PEDGRP.DAT': groups(57), 'CARGRP.DAT': groups(34),
                       'POPCYCLE.DAT': cycle(), 'INFO.ZON': ZONE, 'MAP.ZON': ZONE}
            for name, text in sources.items(): (data / name).write_text(text)
            output = root / 'local-only/tables.json'
            self.assertEqual(prepare(root / 'game', output)['status'], 'PREPARED')
            held = output.read_bytes(); parsed = json.loads(held)
            self.assertEqual(len(parsed['cycleRows']), 480)
            self.assertEqual(prepare(root / 'game', output)['status'], 'REUSED')
            (data / 'CARGRP.DAT').write_text(groups(34, 'gamma'))
            with self.assertRaises(ValueError): prepare(root / 'game', output)
            self.assertEqual(output.read_bytes(), held)
            self.assertEqual((data / 'PEDGRP.DAT').read_text(), sources['PEDGRP.DAT'])
            self.assertEqual(list(output.parent.glob('*.partial')), [])

    def test_preparation_rejects_source_replacement_and_invalid_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); data = root / 'data'; data.mkdir()
            for name in ['pedgrp.dat', 'cargrp.dat', 'popcycle.dat', 'info.zon', 'map.zon']:
                (data / name).write_text('untouched')
            with self.assertRaises(ValueError): prepare(root, data / 'pedgrp.dat')
            self.assertEqual((data / 'pedgrp.dat').read_text(), 'untouched')
            # This remains a missing/invalid source test on case-insensitive FS.
            (data / 'POPcycle.DAT').write_text('bad table')
            with self.assertRaises(ValueError): prepare(root, root / 'local-only/output.json')

    def test_original_derived_output_cannot_enter_public_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); data = root / 'data'; data.mkdir()
            fixtures = {'pedgrp.dat': groups(57), 'cargrp.dat': groups(34),
                        'popcycle.dat': cycle(), 'info.zon': ZONE, 'map.zon': ZONE}
            for name, text in fixtures.items(): (data / name).write_text(text)
            output = ROOT / ('should-never-publish-population-' + uuid.uuid4().hex + '.json')
            try:
                with self.assertRaises(ValueError): prepare(root, output)
                self.assertFalse(output.exists())
            finally:
                output.unlink(missing_ok=True)  # Also preserves failed old-source witnesses.


if __name__ == '__main__':
    unittest.main()
