#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored miniature SCM files; no original script or zone data is embedded."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.assets.original_population import parse_zones
from tools.assets.original_zone_initialization import compile_zone_settings, decode_initialization, zone_index
from tools.assets.prepare_population_tables import prepare
from tests.resources.test_population_tables import cycle, groups


def number(value, tag=1):
    return bytes([tag]) + int(value).to_bytes({1: 4, 4: 1, 5: 2}[tag], 'little', signed=True)


def text(value, padding=b'\0'):
    raw = value.encode('ascii')
    return b'\x09' + (raw + b'\0' + padding * 8)[:8]


def command(opcode, *arguments):
    return struct.pack('<H', opcode) + b''.join(arguments)


NAME = command(0x3a4, text('INITIAL'))
RESET = command(0x8ca)
STOP = command(0x4e)
SET = command(0x767, text('SYNTH'), number(3, 4))
ZONE = 'zone\nsynth, 0, -10.8, -20, -5, 10.8, 20, 5, 1, LABEL\nend\n'


def script(body=None):
    """Six typed headers plus a tiny declared INITIAL, built independently."""
    initial = NAME + (RESET + SET + STOP if body is None else body)
    main = command(0x3a4, text('MAIN')) + STOP
    begin = 68 + len(main)
    result = bytearray()
    for kind in (ord('s'), 0, 1, 2, 3, 4):
        payload = struct.pack('<IIHHII', begin, len(initial), 1, 0, 0, begin) if kind == 1 else b''
        result += b'\x02\0\x01' + struct.pack('<I', len(result) + 8 + len(payload)) + bytes([kind]) + payload
    assert len(result) == 68
    return bytes(result) + main + initial, begin


def decoded(body=None):
    return decode_initialization(script(body)[0])


def configured(operations=None, zones=ZONE):
    data = decoded()
    if operations is not None:
        data['operations'] = operations
    return compile_zone_settings(parse_zones(zones), data)


class ZoneInitialization(unittest.TestCase):
    def test_literal_block_and_no_execution(self):
        result = decoded()
        self.assertEqual(result['operations'], [dict(opcode=0x767, key='SYNTH', values=[3])])
        self.assertEqual(result['proof']['instructions'], 4)
        self.assertFalse(result['proof']['runtimeExecution'])
        self.assertTrue(result['proof']['resetDominatesTerminators'])
        self.assertTrue(result['proof']['singleLiteralBlock'])

    def test_ordered_overwrites_and_shared_info_identity(self):
        body = RESET + SET + command(0x767, text('SYNTH'), number(19))
        body += command(0x76a, text('SYNTH'), number(200, 5))
        body += command(0x76c, text('SYNTH'), number(9, 4), number(123, 5))
        body += command(0x874, text('SYNTH'), number(6, 4))
        body += command(0x9b7, text('SYNTH'), number(1, 4)) + STOP
        zones = ZONE.replace('end', 'SYNTH, 0, 30, 30, -5, 40, 40, 5, 1, OTHER\nend')
        profile = compile_zone_settings(parse_zones(zones), decoded(body))
        self.assertEqual(len(profile['engineZones']), 3)
        self.assertEqual(len(profile['byInfoKey']), 2)
        self.assertEqual(profile['byInfoKey']['SYNTH'], dict(populationType=19, raceMask=6,
                         noCops=True, dealerStrength=200, gangStrength=[0] * 9 + [123]))
        self.assertEqual(profile['literalOperations'], 6)

    def test_defaults_keys_and_float_to_short_bounds(self):
        zones = ZONE.replace('end', 'LongKey8, 0, -32768.5, -2.9, -1, 32767.5, 2.9, 1, 2, TextKey8\nend')
        profile = configured(zones=zones)
        self.assertEqual(profile['engineZones'][1]['infoKey'], 'SYNTH')
        self.assertEqual(profile['engineZones'][2]['textKey'], 'TEXTKEY')
        self.assertEqual(profile['engineZones'][2]['minimum'], [-32768, -2, -1])
        self.assertEqual(profile['engineZones'][2]['maximum'], [32767, 2, 1])
        self.assertEqual(profile['byInfoKey']['LONGKEY'], dict(populationType=5, raceMask=15,
                         noCops=False, dealerStrength=0, gangStrength=[0] * 10))
        self.assertEqual(profile['byInfoKey']['SAN_AND']['populationType'], 5)

    def test_lookup_inclusive_short_bounds_float32_and_root_fallback(self):
        profile = configured()
        for point in [[-10, -20, -5], [10, 20, 5], [0, 0, 0], [10 + 1e-8, 20, 5]]:
            self.assertEqual(zone_index(profile, point), 1)
        for point in [[-10.1, 0, 0], [0, 0, 5.1], [50000, 50000, 50000]]:
            self.assertEqual(zone_index(profile, point), 0)

    def test_lookup_width_plus_height_not_area_and_stable_ties(self):
        # A: area 100, width+height 101. B: area 400, width+height 40.
        zones = ('zone\nSYNTH,0,0,0,0,100,1,5,1,A\n'
                 'B,0,0,0,0,20,20,5,1,B\nC,0,0,0,0,25,15,5,1,C\nend')
        profile = configured(zones=zones)
        self.assertEqual(zone_index(profile, [.5, .5, 0]), 2)
        self.assertEqual(zone_index(profile, [22, .5, 0]), 3)

    def test_literal_string_ends_at_null_not_compiler_padding(self):
        result = decoded(RESET + command(0x767, text('SYNTH', b'X'), number(7)) + STOP)
        self.assertEqual(result['operations'][0]['key'], 'SYNTH')

    def test_positive_and_negative_labels_skip_unreachable_bytes(self):
        for relative in (False, True):
            raw, begin = script()
            target = len(NAME) + 7 + 4
            label = -target if relative else begin + target
            body = command(2, number(label)) + b'\xff' * 4 + RESET + SET + STOP
            result = decoded(body)
            self.assertEqual(len(result['operations']), 1)
            self.assertEqual(result['proof']['instructions'], 5)

    def test_real_cfg_accepts_pre_setup_branch_and_cycle(self):
        # Both conditional paths converge on reset; the prelude may cycle.
        at_branch = len(NAME)
        reset_at = at_branch + 14
        body = command(0x4d, number(-reset_at)) + command(2, number(-at_branch))
        result = decoded(body + RESET + SET + STOP)
        self.assertEqual(result['proof']['instructions'], 6)

    def test_argument_tags_are_skipped_with_exact_extents(self):
        extra = b''
        for tag, count in {2: 2, 3: 2, 7: 6, 8: 6, 10: 2, 11: 2,
                           12: 6, 13: 6, 16: 2, 17: 2, 18: 6, 19: 6}.items():
            extra += command(0x4, bytes([tag]) + bytes(count), number(0))
        for argument in [b'\x06' + struct.pack('<f', 1.5), b'\x0e\x03abc', b'\x0f' + b'Q' * 16]:
            extra += command(0x4, argument, number(0))
        self.assertEqual(len(decoded(extra + RESET + SET + STOP)['operations']), 1)

    def test_zone_byte_pattern_in_argument_is_not_an_operation(self):
        fake = b'\x67\x07\x09ABC\0\0\0\0\0\x04\x05'
        body = command(0x4, b'\x0e' + bytes([len(fake)]) + fake, number(0)) + RESET + SET + STOP
        self.assertEqual(len(decoded(body)['operations']), 1)

    def test_truncated_script_never_emits_partial_configuration(self):
        data, _ = script()
        for length in range(len(data)):
            with self.subTest(length=length), self.assertRaises(ValueError):
                decode_initialization(data[:length])

    def test_header_order_count_boundary_and_largest_mission(self):
        data, _ = script()
        for offset, value in [(7, b'z'), (15, b'\x01'), (23, b'\x03'),
                              (32, struct.pack('<H', 0)), (32, struct.pack('<H', 4097)),
                              (34, struct.pack('<H', 2)), (24, struct.pack('<I', 1)),
                              (28, struct.pack('<I', 1)), (40, struct.pack('<I', len(data)))]:
            bad = bytearray(data); bad[offset:offset + len(value)] = value
            with self.subTest(offset=offset, value=value), self.assertRaises(ValueError):
                decode_initialization(bytes(bad))

    def test_wrong_main_and_initial_identity(self):
        data, _ = script()
        for old, new in [(b'MAIN', b'FAIL'), (b'INITIAL', b'UNKNOWN')]:
            with self.assertRaises(ValueError): decode_initialization(data.replace(old, new))

    def test_unsupported_syntax_negation_and_nonfinite_values(self):
        for body in [command(0x7fff), command(0x8767, text('SYNTH'), number(3)),
                     command(0x8002, number(0)), command(0x8004, b'\0', number(0)),
                     command(0x4, b'\x06' + struct.pack('<f', float('nan')), number(0))]:
            with self.subTest(body=body), self.assertRaises(ValueError): decoded(body + RESET + SET + STOP)

    def test_zone_assignments_require_short_string_and_literal_integer(self):
        for key, value in [(b'\x0e\x05SYNTH', number(2)), (text('lower'), number(2)),
                           (text(''), number(2)), (text('SYNTH'), b'\x02\0\0'),
                           (text('SYNTH'), b'\x06' + struct.pack('<f', 2.0))]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                decoded(RESET + command(0x767, key, value) + STOP)

    def test_missing_duplicate_reset_or_missing_population_is_rejected(self):
        for body in [SET + STOP, RESET + RESET + SET + STOP, RESET + STOP,
                     RESET + command(0x76a, text('SYNTH'), number(0)) + STOP]:
            with self.subTest(body=body), self.assertRaises(ValueError): decoded(body)

    def test_reset_must_dominate_all_terminators(self):
        last = len(NAME) + 7 + len(RESET + SET)
        with self.assertRaisesRegex(ValueError, 'bypassed'):
            decoded(command(0x4d, number(-last)) + RESET + SET + STOP)

    def test_split_configuration_and_reentry_into_partial_block_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'split/conditional'):
            decoded(RESET + SET + command(0xd6, number(0, 4)) + SET + STOP)
        # Reset dominates exits, but after the block a conditional jumps into SET.
        body = RESET + SET + command(0x4d, number(-(len(NAME) + len(RESET)))) + STOP
        with self.assertRaisesRegex(ValueError, 'partial setup'): decoded(body)

    def test_branch_into_argument_or_outside_initializer_is_rejected(self):
        for label in [0, 0x7fffffff, -(len(NAME) + 1), -(len(NAME) + 9)]:
            with self.subTest(label=label), self.assertRaises(ValueError):
                decoded(command(0x4d, number(label)) + RESET + SET + STOP)
        with self.assertRaisesRegex(ValueError, 'nonliteral branch'):
            decoded(command(2, b'\x02\0\0') + RESET + SET + STOP)

    def test_operation_ranges_and_shapes_are_not_silently_clamped(self):
        for opcode, values in [(0x767, [-1]), (0x767, [20]), (0x76a, [256]), (0x76a, [-1]),
                               (0x76c, [10, 1]), (0x76c, [0, 256]), (0x874, [16]),
                               (0x9b7, [2]), (0x767, [True]), (0x767, []), (0x767, [1, 2])]:
            with self.subTest(opcode=opcode, values=values), self.assertRaises(ValueError):
                configured([dict(opcode=opcode, key='SYNTH', values=values)])
        with self.assertRaisesRegex(ValueError, 'no source zone'):
            configured([dict(opcode=0x767, key='MISSING', values=[1])])

    def test_coordinates_reject_nonfinite_extreme_and_wrong_shapes(self):
        profile = configured()
        for value in [float('inf'), float('nan'), 1e300, 10 ** 1000, True, '0']:
            with self.subTest(value=str(value)[:30]), self.assertRaises(ValueError):
                zone_index(profile, [value, 0, 0])
        for position in [None, [], [1, 2], [1, 2, 3, 4]]:
            with self.assertRaises(ValueError): zone_index(profile, position)
        for bounds in [[32768, 0, 0], [-32769, 0, 0], [float('inf'), 0, 0], [0, 0]]:
            zones = parse_zones(ZONE); zones[0]['minimum'] = bounds
            with self.assertRaises(ValueError): compile_zone_settings(zones, decoded())

    def test_optional_preparation_preserves_v1_and_exclusively_publishes_v2(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); data = root / 'game/data'; data.mkdir(parents=True)
            sources = {'pedgrp.dat': groups(57), 'cargrp.dat': groups(34),
                       'popcycle.dat': cycle(), 'info.zon': ZONE, 'map.zon': ZONE}
            for name, value in sources.items(): (data / name).write_text(value)
            scm = root / 'owned.scm'; scm.write_bytes(script()[0]); held = scm.read_bytes()
            v1, v2 = root / 'one.json', root / 'two.json'
            prepare(root / 'game', v1)
            before = v1.read_bytes()
            report = prepare(root / 'game', v2, scm)
            result = json.loads(v2.read_bytes())
            self.assertEqual(json.loads(before)['version'], 1)
            self.assertEqual(result['version'], 2)
            self.assertEqual(result['zoneConfiguration']['byInfoKey']['SYNTH']['populationType'], 3)
            self.assertEqual(result['sourceSHA256']['data/script/main.scm'], hashlib.sha256(held).hexdigest())
            self.assertEqual(report['literalZoneOperations'], 1)
            self.assertEqual(prepare(root / 'game', v2, scm)['status'], 'REUSED')
            with self.assertRaises(ValueError): prepare(root / 'game', v1, scm)
            with self.assertRaises(ValueError): prepare(root / 'game', scm, scm)
            self.assertEqual(prepare(root / 'game', v1)['status'], 'REUSED')
            self.assertEqual(v1.read_bytes(), before)
            self.assertEqual(scm.read_bytes(), held)
            completed = subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_population_tables.py'),
                '--game-dir', str(root / 'game'), '--output', str(v2), '--initial-scm', str(scm)],
                capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(completed.stdout)['status'], 'REUSED')


if __name__ == '__main__':
    unittest.main()
