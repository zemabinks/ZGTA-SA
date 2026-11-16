#!/usr/bin/env python3
"""Actual Renderer support callbacks, native controller/world and imported meshes."""
from pathlib import Path
import hashlib,json,os,platform,subprocess,tempfile
from smoke_native_climb_runtime import function
from smoke_vehicle_coupling import NAMES
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/support-runtime'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    names=NAMES+['NativeVehicleTread','NativeMovingSupport','NativeVehicleSupportScene','NativeFootLocomotion','NativeHeadingContinuity','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController']
    paths=[f'ios/App/{name}.swift' for name in names]+['ios/App/NativeWorldRenderer.swift','smoke_native_support_runtime.swift','smoke_native_support_runtime.py']
    snapshot={p:(ROOT/p).read_bytes() for p in paths}
    renderer=snapshot['ios/App/NativeWorldRenderer.swift'].decode()
    methods='\n'.join(function(renderer,marker) for marker in ['private func configureMovingSupport(','private func synchronizeMovingSupport(','private func remoteSupportPosition(','var footWireSupport:'])
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp);sources=[]
        for name in names:
            p=work/(name+'.swift');p.write_bytes(snapshot[f'ios/App/{name}.swift']);sources.append(str(p))
        main=work/'main.swift';main.write_text(snapshot['smoke_native_support_runtime.swift'].decode().replace('// ACTUAL_CALLBACKS',methods));sources.append(str(main))
        compiled=subprocess.run(['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-target',platform.machine()+'-apple-macosx13.0','-module-cache-path',str(OUT/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,'-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],capture_output=True,text=True)
        (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
        result=subprocess.run([str(work/'verify'),str(ROOT)],capture_output=True,text=True)
        unchanged=all((ROOT/p).read_bytes()==data for p,data in snapshot.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(data).hexdigest() for p,data in snapshot.items()},'output':result.stdout+result.stderr,
                'limits':['Actual native physical world, parked bodies, imported local support geometry and extracted Renderer callback methods','The knock animator is an explicit recording double; clip/blend behavior is covered by separate actual animation gates','No GPU, retail executable, iPhone input or live network claim']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
