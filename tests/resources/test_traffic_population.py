#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored prepared metadata, file-presence and complete graph admission."""
from pathlib import Path
import hashlib
import json
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.assets.prepare_traffic_population import prepare

def roads():
    result = bytearray(struct.pack('<8I', 0x44524453, 1, 4, 4, 4, 0, 0, 0))
    def section(values, code):
        result.extend(struct.pack('<'+str(len(values))+code, *values))
        result.extend(b'\0'*(-len(result)%4))
    section([0,0,104,320,0,104,320,320,104,0,320,104], 'h')
    section([0,1,2,3,4], 'I');section([0,0,0,0], 'I');section([0,0,0,0], 'B')
    section([1,2,3,0], 'I');section([0,1,2,3], 'I');section([160,0,320,160,160,320,0,160], 'h')
    section([1,2,3,0], 'I');section([100,0,0,100,-100,0,0,-100], 'b');section([256]*4, 'I')
    return result

class TrafficPreparation(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='zgta-authored-traffic-')
        self.site = Path(self.temporary.name)
        self.models = self.site/'game/native/models'
        self.models.mkdir(parents=True)
        (self.site/'game/world').mkdir()
        self.source = hashlib.sha256(b'authored source identity').hexdigest()
        self.physics = {'models': {'410': dict(id=410, model='authored_car', kind='car', dffSHA256=self.source,
            bounds={'box': {'min': [-1,-2,-.5], 'max': [1,2,1]}})}}
        self.rig = dict(version=2, id=410, model='authored_car', kind='car', dffSHA256=self.source,
                        paint={'defaults': [1,2], 'colorVariants': [[3,4],[3,4],[1,2],[0x1000000,4]]})
        (self.models/'index.json').write_text(json.dumps({'vehicles': {'410':'authored_car'}}))
        (self.models/'authored_car.rig.bin').write_bytes(b'authored presence fixture, not a GPU mesh')
        (self.models/'authored_car.rig.png').write_bytes(b'authored presence fixture, not a decoded image')
        (self.models/'authored_car.bin').write_bytes(b'authored base presence fixture')
        (self.models/'authored_car.png').write_bytes(b'authored base image presence fixture')
        (self.site/'game/world/roads.bin').write_bytes(roads())
        self.save()
    def save(self):
        (self.site/'game/native/vehicles.physics.json').write_text(json.dumps(self.physics))
        (self.models/'authored_car.rig.json').write_text(json.dumps(self.rig))
    def tearDown(self):
        self.temporary.cleanup()
    def test_dimensions_colors_and_private_provenance(self):
        config=prepare(self.site,[410],4,2)
        self.assertEqual(config['models'],[dict(id=410,length=4,width=2,colors=[[3,4],[1,2]])])
        self.assertEqual((config['maximum'],config['perObserver']),(4,2))
        self.assertEqual(len(config['sourceHashes']),4)
    def test_missing_model_file(self):
        (self.models/'authored_car.rig.bin').unlink()
        with self.assertRaises(ValueError):prepare(self.site,[410])
    def test_missing_required_base_family(self):
        (self.models/'authored_car.bin').unlink()
        with self.assertRaises(ValueError):prepare(self.site,[410])
    def test_different_original_identity(self):
        self.rig['dffSHA256']='0'*64;self.save()
        with self.assertRaises(ValueError):prepare(self.site,[410])
    def test_different_model(self):
        self.rig['id']=411;self.save()
        with self.assertRaises(ValueError):prepare(self.site,[410])
    def test_unsupported_kind(self):
        self.physics['models']['410']['kind']='boat';self.save()
        with self.assertRaises(ValueError):prepare(self.site,[410])
    def test_unavailable_requested_identity(self):
        with self.assertRaises(ValueError):prepare(self.site,[411])
    def test_no_valid_colors(self):
        self.rig['paint']={'defaults':[True,2],'colorVariants':[[1,-1]]};self.save()
        with self.assertRaises(ValueError):prepare(self.site,[410])
    def test_full_graph_validation(self):
        data=bytearray(roads());struct.pack_into('<I',data,96,9999)
        (self.site/'game/world/roads.bin').write_bytes(data)
        with self.assertRaises(ValueError):prepare(self.site,[410])
    def test_budget(self):
        for maximum,count in [(65,1),(1,17),(-1,1)]:
            with self.assertRaises(ValueError):prepare(self.site,[410],maximum,count)

if __name__=='__main__':
    unittest.main()
