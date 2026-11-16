#!/usr/bin/env python3
"""Replay actual parked-trailer support and lifecycle against native bodies."""
from pathlib import Path
import hashlib,json,os,platform,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/vehicle-support'
NAMES=['SwiftRapierWorld','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle',
       'NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces',
       'NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics']
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    paths=[ROOT/'ios/App'/(name+'.swift') for name in NAMES]
    paths += [Path(__file__),ROOT/'smoke_native_vehicle_support.js',ROOT/'smoke_native_vehicle_support.swift',ROOT/'smoke_unattended_vehicles.js',ROOT/'native-physics/include/ZGTARapier.h']
    before={str(p.relative_to(ROOT)):p.read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp);reference=work/'reference.json'
        subprocess.run(['node',str(ROOT/'smoke_native_vehicle_support.js'),str(reference)],cwd=ROOT,check=True)
        sources=[]
        for name in NAMES:
            p=work/(name+'.swift');p.write_bytes(before['ios/App/'+name+'.swift']);sources.append(str(p))
        main=work/'main.swift';main.write_bytes(before['smoke_native_vehicle_support.swift']);sources.append(str(main))
        environment=os.environ.copy();environment.pop('SDKROOT',None)
        command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-target',platform.machine()+'-apple-macosx13.0',
                 '-module-cache-path',str(OUT/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,
                 '-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics',
                 '-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
        compiled=subprocess.run(command,env=environment,capture_output=True,text=True)
        (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr);compiled.check_returncode()
        result=subprocess.run([str(work/'verify'),str(ROOT),str(reference)],capture_output=True,text=True)
        unchanged=all((ROOT/name).read_bytes()==data for name,data in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,
                'sourceHashes':{name:hashlib.sha256(value).hexdigest() for name,value in before.items()},
                'output':result.stdout+result.stderr,'limits':['Actual archived manager and native physical bodies; no original retail or physical device runtime','Support-removal cases are controlled mechanism ablations']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (OUT/'reference.json').write_bytes(reference.read_bytes())
        print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged,'Source changed during support gate'
if __name__=='__main__':main()
