#!/usr/bin/env python3
"""Real native Rapier placement and extracted Renderer/GameVC exit ownership."""
from pathlib import Path
import hashlib,json,platform,subprocess,tempfile
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent
def main():
 out=ROOT/'local-only/native-physics/tests/exit-runtime';out.mkdir(parents=True,exist_ok=True)
 names=['SwiftRapierWorld','NativeWorldRay','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativePersonalFlightController','NativeFootLocomotion','NativeHeadingContinuity','NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeRiderAnimation']
 paths=[f'ios/App/{n}.swift' for n in names]+['ios/App/NativeSkeletalActor.swift','ios/App/NativeWorldRenderer.swift','ios/App/NativeGameViewController.swift','ios/App/NativeMultiplayerClient.swift','smoke_native_bike_exit.swift','smoke_native_exit_runtime.py','smoke_native_exit_runtime.swift']
 before={p:(ROOT/p).read_bytes() for p in paths};skeletal=before['ios/App/NativeSkeletalActor.swift'].decode()
 source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')+'\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
 renderer=before['ios/App/NativeWorldRenderer.swift'].decode();vc=before['ios/App/NativeGameViewController.swift'].decode()
 source+='\nimport CoreFoundation\n'+function(before['ios/App/NativeMultiplayerClient.swift'].decode(),'struct NativeHealthPrediction {')
 harness=before['smoke_native_bike_exit.swift'].decode().split('let root=URL(')[0]
 harness=harness.replace(' func resolveVehicleExit(wanted:SIMD3<Float>?)->NativeVehicleExitPlanner.Placement{.ready(wanted)}',function(renderer,'    private func resolveVehicleExit('))
 harness=harness.replace(' func deferVehicleExit(_ retry:@escaping()->Void){pendingExitPlacement=retry}',function(renderer,'    func deferVehicleExit('))
 harness=harness.replace(' // ACTUAL_RENDERER_EXIT','\n'.join(function(renderer,m) for m in ['    func exitVehicle(','    private func dispatchOwnedVehicleExit(','    private func discardOwnedVehicle('])+'\n func discard(){discardOwnedVehicle()}')
 harness=harness.replace('// ACTUAL_CONTROLLER_EXIT',function(vc,'    private func completeVehicleExit('))
 harness=harness.replace('var direction:Float{driving ? heading:actorHeading}',function(renderer,'    var direction:')).replace('var legacyVehicleQuaternion:SIMD4<Float>?{nil}',function(renderer,'    var legacyVehicleQuaternion:'))
 harness=harness.replace(' let collision:ExitCollision?=ExitCollision()', ''' var riderDefinitions:NativeRiderDefinitions?
 var geometryReady=true,missingCells=Set<String>(),requestedCells=Set<String>()
 var riderDoorHolds:[String:[Int:Double]]=[:]
 func worldRay(from start:SIMD3<Float>,direction:SIMD3<Float>,distance:Float,groups:UInt32)->NativeWorldRay.Result {
  if let coverage=NativeWorldRay.coverage(from:start,to:start+direction*distance,interior:false,loaded:{_ in true}){requestedCells.formUnion(coverage.cells)}
  let world=groundVehicle!.world
  return NativeWorldRay.query(from:start,direction:direction,distance:distance,interior:false,loaded:{self.geometryReady && !self.missingCells.contains($0)}) {p,way,d in
   world.raycast(origin:SwiftRapierWorld.gtaToRapier(p),direction:SwiftRapierWorld.gtaToRapier(way),distance:d,groups:groups).map{.init(distance:$0.distance,normal:SwiftRapierWorld.rapierToGTA($0.normal))}
  }
 }
 func resolve(wanted:SIMD3<Float>?)->NativeVehicleExitPlanner.Placement{resolveVehicleExit(wanted:wanted)}
 let collision:ExitCollision?=ExitCollision()''')
 source+='\n'+harness+'\n'+before['smoke_native_exit_runtime.swift'].decode()
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
  report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(v).hexdigest() for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual native placement/Renderer exit/GameVC completion with real imported collision rows, Rapier, motor and clips','Cell residency is controlled through actual NativeWorldRay; outer UI/network owners are explicit spies','No full rendered scene/streaming scheduler, retail runtime, physical input or device-performance acceptance']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
