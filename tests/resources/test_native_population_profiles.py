#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored original-IDE voice-bank categories through the real local converter."""
from pathlib import Path
import importlib.util,json,os,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('owned_skin_converter',ROOT/'tools/assets/prepare_native_samp_skins.py')
converter=importlib.util.module_from_spec(spec);spec.loader.exec_module(converter)

class PopulationProfiles(unittest.TestCase):
    def test_voice_bank_category_and_missing_metadata(self):
        folder=ROOT/'local-only/research/population-profile-tests-160';folder.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=folder)as work:
            work=Path(work)
            # Identifiers/names are authored. Generic female/prostitute banks
            # qualify; specialized or absent banks must not be guessed by name.
            rows=[(10,'sample_a','CIVFEMALE','PED_TYPE_GEN',True),
                  (11,'sample_b','PROSTITUTE','PED_TYPE_GEN',True),
                  (12,'woman_named','CIVFEMALE','PED_TYPE_SPECIAL',False),
                  (13,'sample_c','CIVMALE','PED_TYPE_GEN',False),
                  (14,'sample_d','GANG1','PED_TYPE_GEN',False),
                  (16,'sample_e','CIVFEMALE','PED_TYPE_GEN',True)]
            lines=['peds']
            for identifier,name,kind,bank,_ in rows:
                fields=[str(identifier),name,name,kind,'STAT_TEST','test','0','0','null','0','0',bank,'VOICE_A','VOICE_B']
                line=', '.join(fields)
                if identifier==16:line=line.replace('0, PED_TYPE_GEN','0 PED_TYPE_GEN')
                lines.append(line)
            lines+=['15, minimal, minimal','end']
            ide=work/'peds.ide';ide.write_text('\n'.join(lines)+'\n')
            index=work/'index.json';index.write_text(json.dumps({'peds':{str(i):name for i,name in [(i,n)for i,n,*_ in rows]+[(15,'minimal')]}}))
            output=work/'samp-skins.json';result=converter.prepare(ide,index,output)
            generated={row['legacyID']:row for row in result['skins']}
            for identifier,name,_,_,expected in rows:
                self.assertEqual(generated[identifier]['model'],name)
                self.assertEqual(generated[identifier]['nativeID'],identifier)
                self.assertIs(generated[identifier]['femaleActivity'],expected)
            self.assertNotIn('femaleActivity',generated[15])
            self.assertEqual(json.loads(output.read_text()),result)

if __name__=='__main__':
    os.setpriority(os.PRIO_PROCESS,0,15);unittest.main()
