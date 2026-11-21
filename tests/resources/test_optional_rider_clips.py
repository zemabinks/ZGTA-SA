#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Optional rider clip candidates with authored metadata/parser boundaries."""
from pathlib import Path
import contextlib,importlib.util,io,json,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('seating_under_test',ROOT/'tools/assets/prepare_native_seating.py')
converter=importlib.util.module_from_spec(spec);spec.loader.exec_module(converter)
class OptionalRiderClips(unittest.TestCase):
 def test_candidate_role_does_not_claim_library_availability(self):
  parent=ROOT/'local-only/research/optional-rider-tests-168';parent.mkdir(parents=True,exist_ok=True)
  with tempfile.TemporaryDirectory(dir=parent)as work:
   work=Path(work);base=work/'local-only/site/game/native';base.mkdir(parents=True)
   (base/'vehicles.physics.json').write_text(json.dumps({'models':{'400':{'kind':'bike','table':{}},'401':{'kind':'car','table':{}},'402':{'kind':'bike','table':{}}}}))
   group={'getIn':['authored:enter'],'getOut':['authored:leave']}
   table={'o':{'400':[0,'authored'],'402':[0,'wayfarer']},'T':[group]}
   oldRoot,oldBundle,oldLiteral=converter.ROOT,converter.bundle_with,converter.json_literal
   try:
    converter.ROOT=work
    converter.bundle_with=lambda marker:(work/'authored.js','authored static metadata')
    converter.json_literal=lambda *args:table
    with contextlib.redirect_stdout(io.StringIO()):converter.main()
   finally:converter.ROOT,converter.bundle_with,converter.json_literal=oldRoot,oldBundle,oldLiteral
   rows=json.loads((base/'seating.json').read_text())['models']
   self.assertEqual(rows['400']['clips']['hit'],'authored/authored_hit')
   self.assertEqual(rows['402']['clips']['hit'],'wayfarer/wf_hit')
   self.assertNotIn('hit',rows['401']['clips'])
   self.assertEqual(rows['400']['clips']['entry'],'authored/enter')
   self.assertEqual(rows['400']['clips']['exit'],'authored/leave')
   self.assertNotIn('available',rows['400'])
if __name__=='__main__':unittest.main()
