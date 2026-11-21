#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual icon decoder/preparation/index selection; independently authored TXDs."""
from pathlib import Path
import copy
import hashlib
import json
import struct
import sys
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
import host
from PIL import Image
from tests.resources.test_native_ped_atlas import txd
from tools.assets import prepare_native_weapon_icons as icons
from tools.assets import prepare_native_resource_package as package

class WeaponIcons(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='zgta-authored-icons-')
        self.root = Path(self.temporary.name).resolve()
        self.local = self.root / 'local-only'
        self.local.mkdir()
        self.game = self.root / 'game'
        self.game.mkdir()
        self.image = Image.new('RGBA', (3, 2))
        self.pixels = [(250, 12, 19, 0), (30, 210, 7, 99), (12, 9, 255, 255), (10, 20, 30, 1), (1, 2, 3, 180), (99, 88, 77, 255)]
        self.image.putdata(self.pixels)
        (self.game / 'authored.txd').write_bytes(txd({'surface':Image.new('RGBA', (1,1)), 'AUTHOREDicon':self.image}))
        (self.game / 'hud.txd').write_bytes(txd({'fist':self.image}))
        self.rows = [dict(id=0, icon=True, modelName=None), dict(id=25, icon=True, modelName='authored')]
        self.catalog = self.root / 'definitions.json'
        self.output = self.local / 'native-weapon-icons'
        self.save_catalog()

    def tearDown(self):
        self.temporary.cleanup()

    def save_catalog(self, rows=None):
        self.catalog.write_text(json.dumps(dict(definitions=rows if rows is not None else self.rows)))

    def prepare(self, output=None):
        return icons.prepare(self.catalog, self.game, output or self.output, self.local)

    def test_exact_sprite_pixels_resolution_and_index(self):
        inputs = {p:p.read_bytes() for p in [self.catalog, self.game/'authored.txd', self.game/'hud.txd']}
        manifest = self.prepare()
        self.assertEqual([row['id'] for row in manifest['icons']], [0,25])
        for row in manifest['icons']:
            with Image.open(self.output/row['file']) as image:
                self.assertEqual(image.size, (3,2))
                self.assertEqual(list(image.convert('RGBA').getdata()), self.pixels)
        self.assertEqual(icons.candidates(self.local), package.candidates(self.local))
        self.assertEqual(set(package.candidates(self.local)), {'reference/weapons/0.png','reference/weapons/25.png'})
        for p, data in inputs.items():
            self.assertEqual(p.read_bytes(), data)
        other = self.local/'repeat'
        self.prepare(other)
        self.assertEqual((self.output/'manifest.json').read_bytes(), (other/'manifest.json').read_bytes())

    def test_missing_exact_sprite_is_atomic(self):
        (self.game/'authored.txd').write_bytes(txd({'unrelated_icon':self.image}))
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.local.glob('.weapon-icons-*')))

    def test_invalid_identity_and_paths(self):
        for row in [dict(id=True,icon=True,modelName='authored'), dict(id=47,icon=True,modelName='authored'), dict(id=25,icon=True,modelName='../escape'), self.rows[1]]:
            with self.subTest(row=row):
                self.save_catalog([self.rows[1], row] if row == self.rows[1] else [row])
                with self.assertRaises(ValueError):
                    self.prepare()
                self.assertFalse(self.output.exists())
        self.save_catalog()
        for target in [self.root/'outside',self.local/'..'/'escaped',self.local]:
            with self.assertRaises(ValueError):
                self.prepare(target)
        (self.local/'linked').symlink_to(self.game, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.prepare(self.local/'linked'/'output')

    def test_existing_output_and_content_tamper(self):
        self.prepare()
        before = (self.output/'manifest.json').read_bytes()
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual((self.output/'manifest.json').read_bytes(), before)
        path = self.output/'25.png'
        raw = path.read_bytes()
        path.write_bytes(raw[:-1]+bytes([raw[-1]^1]))
        with self.assertRaises(ValueError):
            icons.candidates(self.local)

    def test_if_needed_creates_then_reuses_without_decode_or_writes(self):
        manifest, reused = icons.prepare_if_needed(self.catalog, self.game, self.output, self.local)
        self.assertFalse(reused)
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.output.iterdir()}
        with mock.patch.object(icons, 'textures', side_effect=AssertionError('Unchanged icons decoded again')):
            current, reused = icons.prepare_if_needed(self.catalog, self.game, self.output, self.local)
        self.assertTrue(reused)
        self.assertEqual(current, manifest)
        self.assertEqual(before, {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.output.iterdir()})
        self.assertEqual(set(package.candidates(self.local)), {'reference/weapons/0.png', 'reference/weapons/25.png'})

    def test_if_needed_rejects_changed_inputs_and_preserves_output(self):
        self.prepare()
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.output.iterdir()}
        original = self.catalog.read_bytes()
        self.save_catalog([self.rows[0]])
        with self.assertRaisesRegex(ValueError, 'inputs changed'):
            icons.prepare_if_needed(self.catalog, self.game, self.output, self.local)
        self.catalog.write_bytes(original)
        self.image.putpixel((0, 0), (1, 200, 42, 255))
        (self.game/'authored.txd').write_bytes(txd({'AUTHOREDicon': self.image}))
        with self.assertRaisesRegex(ValueError, 'source changed'):
            icons.prepare_if_needed(self.catalog, self.game, self.output, self.local)
        self.assertEqual(before, {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.output.iterdir()})
        self.assertFalse(list(self.local.glob('.weapon-icons-*')))

    def test_if_needed_rejects_corruption_and_symlink_output(self):
        self.prepare()
        icon = self.output/'25.png'
        raw = icon.read_bytes()
        icon.write_bytes(raw[:-1]+bytes([raw[-1]^1]))
        before = {p.name: p.read_bytes() for p in self.output.iterdir()}
        with self.assertRaisesRegex(ValueError, 'identity changed'):
            icons.prepare_if_needed(self.catalog, self.game, self.output, self.local)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.output.iterdir()})
        linked = self.local/'linked-output'
        linked.symlink_to(self.output, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            icons.prepare_if_needed(self.catalog, self.game, linked, self.local)

    def test_native_setup_dispatches_icons_after_definitions_before_package(self):
        calls = []
        args = SimpleNamespace(import_site=None, download=False, native=True)
        with mock.patch.object(host, 'node'), mock.patch.object(host, 'require_assets'), mock.patch.object(host, 'run', side_effect=lambda *command: calls.append(command)), mock.patch('builtins.print'):
            host.setup(args)
        icon = ('tools/assets/prepare_native_weapon_icons.py', '--catalog', 'local-only/site/game/native/weapons.json', '--game', 'local-only/site/game', '--if-needed')
        self.assertEqual(calls.count(icon), 1)
        self.assertLess(calls.index(('tools/assets/prepare_native_weapons.py',)), calls.index(icon))
        self.assertLess(calls.index(icon), calls.index(('tools/assets/prepare_native_resource_package.py',)))
        calls.clear()
        args.native = False
        with mock.patch.object(host, 'node'), mock.patch.object(host, 'require_assets'), mock.patch.object(host, 'run', side_effect=lambda *command: calls.append(command)), mock.patch('builtins.print'):
            host.setup(args)
        self.assertFalse(any('weapon_icons' in command[0] for command in calls))

    def test_manifest_path_dimension_and_symlink_rejection(self):
        manifest = self.prepare()
        for mutation in ['path','dimension','duplicate']:
            value = copy.deepcopy(manifest)
            if mutation=='path':value['icons'][0]['file']='../25.png'
            elif mutation=='dimension':value['icons'][0]['width']=4097
            else:value['icons'].append(copy.deepcopy(value['icons'][0]))
            (self.output/'manifest.json').write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                icons.candidates(self.local)
        (self.output/'manifest.json').write_text(json.dumps(manifest))
        first = self.output/'0.png'
        first.unlink()
        first.symlink_to(self.output/'25.png')
        with self.assertRaises(ValueError):
            icons.candidates(self.local)

    def test_texture_bounds_count_and_truncation(self):
        original = (self.game/'authored.txd').read_bytes()
        root = list(icons.chunks(original,0,len(original)))[0]
        native = next(row for row in icons.children(original,root) if row[0]==21)
        info = icons.first(icons.children(original,native),1)
        large = bytearray(original)
        struct.pack_into('<H',large,info[1]+80,65535)
        directory = icons.first(icons.children(original,root),1)
        wrong_count = bytearray(original)
        struct.pack_into('<H',wrong_count,directory[1],200)
        for data in [original[:-1],bytes(large),bytes(wrong_count),b'not-a-texture']:
            (self.game/'authored.txd').write_bytes(data)
            with self.assertRaises((ValueError,struct.error)):
                self.prepare()
            self.assertFalse(self.output.exists())

if __name__ == '__main__':
    unittest.main()
