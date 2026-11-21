#!/usr/bin/env python3
"""Actual native original/default flavors through isolated real WebSockets."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
NAMES=['ServerAddress','NativeConnectionRecovery','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState','NativeShotTargeting','NativeStreamShotClaims','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeOriginalWorldProtocol','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeOriginalWorldEffects','NativeSAMPLocalVitals','NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots','NativeLocalShotPackets','NativeMultiplayerClient']
def main():
 out=ROOT/'local-only/research/original-world-wire';out.mkdir(parents=True,exist_ok=True)
 paths=['ios/App/'+n+'.swift'for n in NAMES]+['ios/App/NativeActorAnimation.swift','tests/network/smoke_original_world_wire.py','tests/network/smoke_original_world_wire.js','tests/network/smoke_original_world_wire.swift']
 before={p:(ROOT/p).read_bytes()for p in paths}
 with tempfile.TemporaryDirectory(dir=out,prefix='verify-')as temp:
  w=Path(temp);actor=before['ios/App/NativeActorAnimation.swift'].decode();motion=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
  (w/'main.swift').write_text('\n'.join(before['ios/App/'+n+'.swift'].decode()for n in NAMES)+'\n'+motion+'\n'+before['tests/network/smoke_original_world_wire.swift'].decode())
  result=subprocess.run(['xcrun','swiftc','-O','-j','1','-whole-module-optimization','-num-threads','1','-module-cache-path',str(out/'modules'),str(w/'main.swift'),'-o',str(w/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run(['node',str(ROOT/'tests/network/smoke_original_world_wire.js'),str(w/'verify')],capture_output=True,text=True,timeout=40)
  same=all((ROOT/p).read_bytes()==v for p,v in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{p:hashlib.sha256(v).hexdigest()for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual NativeMultiplayerClient and NativeWeaponState through real URLSession WebSockets','Loopback service is a controlled original-protocol fixture, not the original authenticated backend','Original guest login and future-protocol refusal, baseline readiness, binary peers, combat/guns, vehicle release, denied/approved respawn, who and reconnect','Default independent ACK negotiation remains strict; no actual SA-MP/open.mp or original-live gameplay claim']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
