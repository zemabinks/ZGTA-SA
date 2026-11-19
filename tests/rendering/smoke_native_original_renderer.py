#!/usr/bin/env python3
"""Extract actual Renderer skin/damage/quaternion methods with real animation/Rapier."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,platform,subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
def main():
    out=ROOT/'local-only/native-physics/tests/original-renderer';out.mkdir(parents=True,exist_ok=True)
    names=['SwiftRapierWorld','NativeWorldRay','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics','NativeVehiclePaint','NativeVehicleRig','NativeFootLocomotion','NativeHeadingContinuity','NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeSwimController','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeActorSelection','NativeSAMPSkinCatalog','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPGameCamera']
    paths=[f'ios/App/{name}.swift'for name in names]+['ios/App/NativeSkeletalActor.swift','ios/App/NativeWorldRenderer.swift','tests/rendering/smoke_native_original_renderer.py','tests/rendering/smoke_native_original_renderer.swift']
    before={name:(ROOT/name).read_bytes()for name in paths};skeletal=before['ios/App/NativeSkeletalActor.swift'].decode();renderer=before['ios/App/NativeWorldRenderer.swift'].decode()
    source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')+'\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
    source+='''
final class VisibilitySpy {var resets=0;func reset(){resets+=1}}
struct WorldCollision {let label:String}
struct CharacterQuerySpy {let walker:UInt64,probe:UInt64}
struct CharacterSpy {let queries:CharacterQuerySpy?}
final class CameraSpy {var begins=0;func beginVehicle(){begins+=1}}
// Fixed CJ GPU availability is deliberately absent in this renderer/physics
// carrier; the separate CJ runtime gate owns actual assembly/upload admission.
final class UnavailableCJ {var isReady=false}
final class OriginalRenderer {
 let groundVehicle:NativeGroundVehicle?
 var pedModels:[String:String]=[:],vehicleModels:[String:String]=[:],vehicleRigs:[String:NativeVehicleRig]=[:]
 var legacyPedModels:[String:Int]=[:],legacyPedStyles:[String:String]=[:]
 var localSkin=7,localLegacySkin:Int?
 var fixedCJ:UnavailableCJ?=UnavailableCJ()
 func fixedCJSourceIdentity()->String{"authored-renderer-source"}
 func ensureFixedCJ(force:Bool=false){}
 // ACTUAL_SELECTION
 var skeletalLibrary:NativeSkeletalAnimationLibrary?,footDefinitions:NativeFootAnimationDefinitions?
 var footAnimator:NativeFootAnimation?,footAnimationModel=""
 var ownRiderCapture:Int?,ownRiderPrevious:Int?,ownRiderFeet:Int?
 let ownCameraVisibility=VisibilitySpy(),swimController=NativeSwimController(),headingContinuity=NativeHeadingContinuity(),footLocomotion=NativeFootLocomotion()
 var footAnimationFrame:NativeFootAnimation.Frame?
 var actorHeading:Float=0.7,camera=SIMD3<Float>(10,20,3),footAirTime=7.2,footAirFall=13.4,footJumpMinimum=0.9
 var footAirFell=true,footJumped=true,footLaunchRemaining:Double?=0.19,footAirVelocity=SIMD2<Double>(3,7)
 var driving=false,activeVehicleModel="420",vehicleHealth=1000,activeVehicleDamage="",health=100
 var activeModelOrigin:Float=0,vehiclePitch:Float=0,vehicleFallbackRoll:Float=0,drivingSpeed:Float=0,verticalSpeed:Float=0,heading:Float=0.7
 var canNativeFootMeleeGuard=true,meleeGuardHeld=false,meleeBlockHeld=false,weaponTriggerHeld=false
 let gameCamera=CameraSpy()
 var activeDetail="c136",activeDetails=Set<String>(),activeFar=Set<String>(),insideCells=Set(0..<256)
 var collisionScene:Bool?,collisionRequests=NativeCollisionRequests(),desiredPhysicsCells=Set<String>()
 var meshes:[String:Int]=[:],collisions:[String:WorldCollision]=[:],character:CharacterSpy?
 var legacyCameraSample:NativeSAMPGameCamera.Sample?
 var legacySpectating:Bool{legacyCameraSample?.spectating==true}
 var loadedMeshes=Set<String>(),loadedCollisions=Set<String>()
 var onStatus:((String)->Void)?,onFootstep:((String)->Void)?
 var loaded:[String]=[]
 func loadActor(_ name:String){loaded.append(name)}
 func load(name:String){loadedMeshes.insert(name)}
 func loadCollision(name:String){loadedCollisions.insert(name)}
 func teleport(x:Float,y:Float,z:Float,direction:Float?=nil){camera=SIMD3(x,y,z);if let direction{actorHeading=direction}}
 func collision(at point:SIMD3<Float>)->WorldCollision?{collisionFor(point)}
 func trace(from point:SIMD3<Float>,direction:SIMD3<Float>,distance:Float)->NativeWorldRay.Result{worldRay(from:point,direction:direction,distance:distance,groups:0xffff0083)}
 func prepare(){prepareFootAnimation()}
 init(){groundVehicle=NativeGroundVehicle()!}
 // ACTUAL_METHODS
}
'''
    def actual(marker):
        start=renderer.index(marker)
        if 'receiveOriginalVehicleHit' not in marker:return function(renderer,marker)
        # A default closure occurs before the body; skip its braces while
        # retaining the complete production signature and method body.
        body=renderer.index('}) -> Bool {',start)+len('}) -> Bool ')
        prefix=renderer[start:body]
        tail=function(renderer[body:],'{')
        return prefix+tail
    selection=renderer[renderer.index('    private let actorSelection = NativeActorSelection()'):renderer.index('    private var weaponModels:')]
    source=source.replace('// ACTUAL_SELECTION',selection.replace('private ',''))
    source=source.replace('// ACTUAL_METHODS','\n'.join(actual(marker)for marker in[
        '    private func prepareFootAnimation(',
        '    var legacyVehicleQuaternion:', '    @discardableResult func receiveOriginalVehicleHit(',
        '    private func burstOriginalVehicleWheel(',
        '    func canParryOriginalHit(', '    @discardableResult func repairOriginalVehicle(',
        '    @discardableResult func flipOriginalVehicle(', '    func liftOriginalPlayer(',
        '    var networkInterior:', '    private var isInterior:',
        '    private var scenePosition:', '    func loadNearby(', '    private func collisionFor(', '    private func worldRay(']))
    source+='\n'+before['tests/rendering/smoke_native_original_renderer.swift'].decode()
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out)as temporary:
        work=Path(temporary);sources=[]
        for name in names:
            p=work/(name+'.swift');p.write_bytes(before[f'ios/App/{name}.swift']);sources.append(str(p))
        (work/'main.swift').write_text(source);sources.append(str(work/'main.swift'))
        result=subprocess.run(['xcrun','swiftc','-Onone','-whole-module-optimization','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,'-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],capture_output=True,text=True)
        (out/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(ROOT)],capture_output=True,text=True)
        unchanged=all((ROOT/name).read_bytes()==data for name,data in before.items())
        report={'status':'PASS'if result.returncode==0 and unchanged else'FAIL','sourceUnchanged':unchanged,'sourceHashes':{name:hashlib.sha256(data).hexdigest()for name,data in before.items()},'output':result.stdout+result.stderr,'limits':['Actual extracted Renderer methods with real native animation library, rig metadata, damage state and Rapier body queries','Actor loading/Metal visibility are explicit spies; no full rendered or physical-device acceptance','No authenticated original-site gameplay or retail1:1 assertion']}
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
