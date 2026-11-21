#!/usr/bin/env python3
"""Actual URLSession coupling negotiation, topology and ACK ownership."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/coupling-wire';OUT.mkdir(parents=True,exist_ok=True)
NAMES=['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeShotTargeting','NativeStreamShotClaims','NativeOriginalWorldProtocol','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPLocalVitals','NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots','NativeLocalShotPackets','NativeMultiplayerClient']
FILES=[f'ios/App/{n}.swift' for n in NAMES]+['ios/App/NativeActorAnimation.swift','tests/network/smoke_native_coupling_wire.py','tests/network/smoke_native_coupling_wire.js','tests/network/smoke_native_coupling_wire.swift']
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--negative-no-callback-guard',action='store_true');args=parser.parse_args()
 inputs={n:(ROOT/n).read_bytes() for n in FILES}
 with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temp:
  p=Path(temp);actor=inputs['ios/App/NativeActorAnimation.swift'].decode();actor=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
  source='\n'.join(inputs[f'ios/App/{n}.swift'].decode() for n in NAMES)+'\n'+actor+'\n'+inputs['tests/network/smoke_native_coupling_wire.swift'].decode()
  if args.negative_no_callback_guard:
   guard='        guard socket === task,transportGeneration==generation,inventoryConnection==connection,couplingAcknowledgements else{return}\n'
   assert source.count(guard)==1,'Callback ownership boundary changed';source=source.replace(guard,'')
  (p/'main.swift').write_text(source);exe=p/'client'
  compiled=subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'modules'),str(p/'main.swift'),'-o',str(exe)],capture_output=True,text=True)
  (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr)
  if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
  (p/'server.js').write_bytes(inputs['tests/network/smoke_native_coupling_wire.js'])
  result=subprocess.run(['node',str(p/'server.js'),str(exe)],capture_output=True,text=True,timeout=80)
  (OUT/'runtime.log').write_text(result.stdout+result.stderr)
  (OUT/('negative-callback-guard.json' if args.negative_no_callback_guard else 'report.json')).write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
    'sourceHashes':{n:hashlib.sha256(v).hexdigest() for n,v in inputs.items()},
    'liveFilesStillMatchSnapshot':{n:(ROOT/n).read_bytes()==v for n,v in inputs.items()},
    'controlledNegative':args.negative_no_callback_guard,
    'limits':['Actual native URLSession and ephemeral Node HTTP/WebSocket peer with controlled topology/ACK packets','Protocol boundary, not real vehicle joint physics, backend geometry authority, retail runtime or production service','Negative mode removes one guard only in the isolated compiled snapshot; it is not a historical retail/client revision']},indent=2)+'\n')
  print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
if __name__=='__main__':main()
