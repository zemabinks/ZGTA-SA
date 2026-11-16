#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Owner-local original collision and real native motor coordinate calibration."""
from pathlib import Path
import hashlib,json,platform,subprocess,tempfile,sys
ROOT=Path(__file__).resolve().parent
def declaration(source,marker):
 start=source.index(marker);at=source.index('{',start)+1;depth=1
 while depth:depth+=(source[at]=='{')-(source[at]=='}');at+=1
 return source[start:at]
def main():
 if len(sys.argv)!=2:raise SystemExit('Usage: python3 smoke_samp_coordinates.py OWNER_REFERENCE_JSON')
 reference=Path(sys.argv[1]).resolve();records=json.loads(reference.read_text())
 out=ROOT/'local-only/research/samp-ped-height';out.mkdir(parents=True,exist_ok=True)
 names=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController']
 paths=[f'ios/App/{n}.swift'for n in names]+['ios/App/NativeSAMPWorldConnection.swift','smoke_samp_coordinates.py','smoke_samp_coordinates.swift']
 before={p:(ROOT/p).read_bytes()for p in paths};assets={r['collisionFile']:hashlib.sha256((ROOT/r['collisionFile']).read_bytes()).hexdigest()for r in records}
 with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as tmp:
  work=Path(tmp);sources=[]
  for n in names:
   p=work/(n+'.swift');p.write_bytes(before[f'ios/App/{n}.swift']);sources.append(str(p))
  helper=declaration(before['ios/App/NativeSAMPWorldConnection.swift'].decode(),'enum NativeSAMPPedCoordinates {')
  (work/'main.swift').write_text(before['smoke_samp_coordinates.swift'].decode().replace('// ACTUAL_PED_COORDINATES',helper))
  result=subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,str(work/'main.swift'),'-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics','-framework','CoreFoundation','-framework','Security','-o',str(work/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(work/'verify'),str(reference),str(out/'native-observations.json'),str(ROOT)],capture_output=True,text=True)
  same=all((ROOT/p).read_bytes()==b for p,b in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{p:hashlib.sha256(b).hexdigest()for p,b in before.items()},'referenceSHA256':hashlib.sha256(reference.read_bytes()).hexdigest(),'ownerCollisionHashes':assets,'output':result.stdout+result.stderr,'limits':['Actual imported owner-local original collision and actual native Rapier/motor, with previous UIKit/witness positions as references','Source-supported1m CPed model-root/feet coordinate conversion; measured native contact margin remains separate','No original retail executable, animation foot-placement or phone performance/1:1 evidence']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
