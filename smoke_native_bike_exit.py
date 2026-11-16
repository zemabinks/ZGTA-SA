#!/usr/bin/env python3
"""Actual forced-exit methods with real native vehicle/foot physics and clips."""
from pathlib import Path
import hashlib,json,platform,subprocess,tempfile
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent
def main():
    out=ROOT/'local-only/native-physics/tests/bike-exit';out.mkdir(parents=True,exist_ok=True)
    names=['SwiftRapierWorld','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativePersonalFlightController','NativeFootLocomotion','NativeHeadingContinuity','NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation']
    paths=[f'ios/App/{n}.swift' for n in names]+['ios/App/NativeSkeletalActor.swift','ios/App/NativeWorldRenderer.swift','ios/App/NativeGameViewController.swift','ios/App/NativeMultiplayerClient.swift','smoke_native_bike_exit.py','smoke_native_bike_exit.swift']
    before={p:(ROOT/p).read_bytes() for p in paths}
    skeletal=before['ios/App/NativeSkeletalActor.swift'].decode()
    source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')+'\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
    renderer=before['ios/App/NativeWorldRenderer.swift'].decode();vc=before['ios/App/NativeGameViewController.swift'].decode()
    source+='\nimport CoreFoundation\n'+function(before['ios/App/NativeMultiplayerClient.swift'].decode(),'struct NativeHealthPrediction {')
    source+='\n'+before['smoke_native_bike_exit.swift'].decode().replace('// ACTUAL_RENDERER_EXIT',function(renderer,'    func exitVehicle(')+'\n'+function(renderer,'    private func dispatchOwnedVehicleExit(')).replace('// ACTUAL_CONTROLLER_EXIT',function(vc,'    private func completeVehicleExit(')).replace('var direction:Float{driving ? heading:actorHeading}',function(renderer,'    var direction:')).replace('var legacyVehicleQuaternion:SIMD4<Float>?{nil}',function(renderer,'    var legacyVehicleQuaternion:'))
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out) as temp:
        work=Path(temp);sources=[]
        for n in names:
            p=work/(n+'.swift');p.write_bytes(before[f'ios/App/{n}.swift']);sources.append(str(p))
        (work/'main.swift').write_text(source);sources.append(str(work/'main.swift'))
        result=subprocess.run(['xcrun','swiftc','-O','-whole-module-optimization','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,'-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],capture_output=True,text=True)
        (out/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(ROOT)],capture_output=True,text=True)
        unchanged=all((ROOT/p).read_bytes()==v for p,v in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(v).hexdigest() for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual Renderer/controller exit methods and real clips/foot/vehicle/parked physics; outer UI/network owners are explicit spies','No rendered rider alignment, real transport, physical input, retail comparison or device performance evidence']}
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
