# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import json,struct,sys,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.assets.prepare_population import prepare
class Selection(unittest.TestCase):
    def test_original_civilian_identity_required(self):
        with tempfile.TemporaryDirectory()as d:
            root=Path(d)
            for suffix in ['.bin','.png','.skel.bin']:(root/('invented'+suffix)).write_bytes(b'Authored boundary; no actual model acceptance')
            ide=b'7, invented, invented, CIVMALE, STAT_TEST\n8, copfixture, copfixture, COP, STAT_TEST\n9, missing, missing, CIVFEMALE, STAT_TEST\n'
            index=json.dumps(dict(peds={'7':'invented','8':'copfixture','9':'missing','10':'invented','2':'fallback'})).encode()
            graph=struct.pack('<8I',0x44504453,1,1,0,0,0,0,0)+bytes(16)+bytes([0,0,0,0,8,0,0,0])
            config,report=prepare(ide,index,graph,root)
            self.assertEqual(config['models'],[7]);self.assertEqual(report['unavailable'],[9]);self.assertEqual(len(config['pathsCRC32']),8)
            with self.assertRaises(ValueError):prepare(ide+ide,index,graph,root)
            with self.assertRaises(ValueError):prepare(ide,index,b'bad graph',root)
            with self.assertRaises(ValueError):prepare(ide,b'{"peds":{}}',graph,root)
if __name__=='__main__':unittest.main()
