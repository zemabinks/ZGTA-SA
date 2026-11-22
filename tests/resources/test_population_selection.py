# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import json,struct,sys,tempfile,unittest,runpy,subprocess
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.assets.prepare_population import prepare
family=runpy.run_path(str(Path(__file__).with_name('population_model_fixture.py')))['family']
class Selection(unittest.TestCase):
    def test_cli_receipt_admits_actual_backend_and_cannot_replace_sources(self):
        with tempfile.TemporaryDirectory()as temporary:
            root=Path(temporary);site=root/'local-only/site';models=site/'game/native/models';models.mkdir(parents=True)
            graph=struct.pack('<8I',0x44504453,1,1,0,0,0,0,0)+bytes(16)+bytes([0,0,0,0,8,0,0,0])
            (site/'game/world').mkdir();(site/'game/world/paths.bin').write_bytes(graph)
            index=models/'index.json';index.write_text('{"peds":{"7":"invented","9":"missing"}}')
            for suffix,data in zip(['.bin','.png','.skel.bin'],family()):(models/('invented'+suffix)).write_bytes(data)
            ide=root/'peds.ide';ide.write_text('7, invented, invented, CIVMALE, STAT_TEST\n9, missing, missing, CIVFEMALE, STAT_TEST\n')
            output=root/'local-only/selfhost/population.json'
            command=[sys.executable,str(ROOT/'tools/assets/prepare_population.py'),'--peds-ide',str(ide),'--site',str(site),'--out',str(output),'--models','7']
            r=subprocess.run(command,capture_output=True,text=True,check=True,timeout=10)
            self.assertEqual(json.loads(r.stdout)['availableCivilianModels'],1)
            self.assertEqual(len(json.loads(output.read_text())['sourceHashes']),5)
            node="const load=require(process.argv[1]);const p=load(process.argv[2],{ground:()=>0,clear:()=>true});process.stdout.write(JSON.stringify(p.models));"
            r=subprocess.run(['node','-e',node,str(ROOT/'server/population/load.js'),str(root)],capture_output=True,text=True,check=True,timeout=10)
            self.assertEqual(json.loads(r.stdout),[7])
            original=index.read_bytes()
            bad=command.copy();bad[bad.index('--out')+1]=str(index);bad.append('--replace')
            r=subprocess.run(bad,capture_output=True,text=True,timeout=10)
            self.assertNotEqual(r.returncode,0);self.assertIn('cannot replace a source',r.stderr)
            self.assertEqual(index.read_bytes(),original)
            held=output.read_bytes();(models/'invented.skel.bin').write_bytes(b'')
            r=subprocess.run(command+['--replace'],capture_output=True,text=True,timeout=10)
            self.assertNotEqual(r.returncode,0);self.assertEqual(output.read_bytes(),held)
            self.assertEqual(list(output.parent.glob('*.partial')),[])

    def test_original_civilian_identity_required(self):
        with tempfile.TemporaryDirectory()as d:
            root=Path(d)
            for suffix,data in zip(['.bin','.png','.skel.bin'],family()):(root/('invented'+suffix)).write_bytes(data)
            ide=b'7, invented, invented, CIVMALE, STAT_TEST\n8, copfixture, copfixture, COP, STAT_TEST\n9, missing, missing, CIVFEMALE, STAT_TEST\n'
            index=json.dumps(dict(peds={'7':'invented','8':'copfixture','9':'missing','10':'invented','2':'fallback'})).encode()
            graph=struct.pack('<8I',0x44504453,1,1,0,0,0,0,0)+bytes(16)+bytes([0,0,0,0,8,0,0,0])
            config,report=prepare(ide,index,graph,root)
            self.assertEqual(config['models'],[7]);self.assertEqual(report['unavailable'],[9]);self.assertEqual(len(config['pathsCRC32']),8)
            self.assertEqual(len(config['sourceHashes']),5)
            self.assertEqual(report['validatedFamilies']['7']['vertices'],3)
            for value in [b'[]',b'null',b'{"peds":[]}']:
                with self.assertRaises(ValueError):prepare(ide,value,graph,root)
            malformed=json.dumps(dict(peds={'007':'invented','999':'invented'})).encode()
            with self.assertRaises(ValueError):prepare(ide,malformed,graph,root)
            self.assertEqual(prepare(ide,index,graph,root,model_ids=[7])[0]['models'],[7])
            for requested in [[],[7,7],[8],[7,9],[True],[-1],[312]]:
                with self.subTest(requested=requested),self.assertRaises(ValueError):prepare(ide,index,graph,root,model_ids=requested)
            (root/'invented.skel.bin').write_bytes(b'')
            with self.assertRaises(ValueError):prepare(ide,index,graph,root)
            with self.assertRaises(ValueError):prepare(ide+ide,index,graph,root)
            with self.assertRaises(ValueError):prepare(ide,index,b'bad graph',root)
            with self.assertRaises(ValueError):prepare(ide,b'{"peds":{}}',graph,root)
if __name__=='__main__':unittest.main()
