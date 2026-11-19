#!/usr/bin/env python3
"""Exercise actual extracted reconnect owner methods with non-UI owner spies.

Transport/HTTP/Rapier behavior has separate real-runtime gates. This checks
controller call ordering, retained pose, discarded ownership and modal lifetime.
Artwork cancellation and renderer world disposal are explicit boundary spies;
their underlying download/GPU/resource implementations are not simulated here.
"""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/connection-owners';OUT.mkdir(parents=True,exist_ok=True)
paths=['ios/App/NativeGameViewController.swift','ios/App/NativeWorldRenderer.swift','ios/App/NativeGameBindings.swift','ios/App/NativeConnectionRecovery.swift','ios/App/NativeOriginalWorldEffects.swift','ios/App/NativeGameplayIdleTimer.swift']
inputs={p:(ROOT/p).read_text() for p in paths}
def method(source,marker):
 start=source.index(marker);brace=source.index('{',start);depth=1;end=brace+1
 while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end].replace('private ','').replace('@objc ','')+'\n'
vc,renderer=inputs[paths[0]],inputs[paths[1]]
code=r'''
import Foundation
import simd
var ownerCalls:[String]=[]
var systemIdleDisabled=false
extension NativeGameplayIdleTimer {
 static let shared=NativeGameplayIdleTimer(read:{systemIdleDisabled},write:{systemIdleDisabled=$0})
}
final class Couplings {
 var owner:String?="old-car",connection:String?="old-connection",removed:[String]=[]
 func setOwnedVehicle(_ id:String?){owner=id;ownerCalls.append("coupling-owner")}
 func reset(connection:String?){self.connection=connection;ownerCalls.append("coupling-reset")}
 func removeVehicle(_ id:String){removed.append(id);ownerCalls.append("coupling-remove")}
}
final class Body {
 var active=true,workingTowed=true,otherIDs:Set<String>=["old-car","parked"];var exits=0,clears=0
 func exit(){active=false;exits+=1;ownerCalls.append("body-exit")}
 @discardableResult func removeOtherVehicle(id:String)->Bool {otherIDs.remove(id) != nil}
 func clearOtherVehicles(){otherIDs=[];clears+=1}
}
final class Flight {var worn=true;func wear(_ value:Bool){worn=value}}
struct Vehicle {let id:String}
final class Camera {var shakeCancels=0;func cancelShake(){shakeCancels+=1};func resumeFoot(from:Int?,fallbackHeading:Float,fallbackPitch:Float)->SIMD2<Float>{SIMD2(fallbackHeading,fallbackPitch)}}
final class Effects {var clears=0;func clear(){clears+=1}}
final class DamageOwner {var resets=0;func reset(){resets+=1}}
final class Renderer {
 var displayResets=0
 func resetDisplayClock(){displayResets+=1}
 var actorSelectionCancels=0
 func cancelActorSelection(){actorSelectionCancels+=1}
 var legacyWorldClears=0
 func clearLegacyWorld(){legacyWorldClears+=1;ownerCalls.append("legacy-world-clear")}
 var networkInterior:Int?=3,actorEffectResets=0
 func setOriginalActorEffects(burning:Bool,coughing:Bool){precondition(!burning && !coughing);actorEffectResets+=1}
 let localHitReaction=DamageOwner();var footDeathKind:String?="old";var pendingFootHit:SIMD3<Double>?=SIMD3(1,2,3)
 let groundVehicle:Body?=Body(),personalFlight=Flight()
 let vehicleCoupling:Couplings?=Couplings()
 var couplingConnection:String?="old-connection",couplingSnapshot:Int?=1
 var passengerSeat:Int?=1,passengerFrame:Int?=1,passengerAccumulator=0.25
 var driving=true,currentVehicleID:String?="old-car",drivingSpeed:Float=25,flightVerticalSpeed:Float=4
 var vehiclePitch:Float=0.2,vehicleFallbackRoll:Float=0.1,activeModelOrigin:Float=1
 var pendingVehicleSnapshot:Int?=1,activeVehicleModel="410",activeHandling:Int?=1,vehicleKind="car"
 var pendingExitPlacement:(()->Void)?={},vehicleExitSerial:UInt64=0
 var pendingVehicleExit:(()->Void)?={},ownRiderPlayback:Int?=1,ownRiderPrevious:Int?=1,ownRiderCapture:Int?=1,ownRiderFeet:Int?=1
 var ownRiderAnimation:Int?=1,vehicleHorn=true,vehicleSiren=true,vehicleHop=true
 var steeringInput:Float=0.8,vehicleWorkingControl:Float=1
 var isPassenger:Bool{passengerSeat != nil};var passengerWirePosition:SIMD3<Float>{camera}
 var direction:Float{driving ? heading:actorHeading}
 var riderDoorHolds=["old-car":1],remotePlayers=[1],remoteVehicles=[Vehicle(id:"old-car"),Vehicle(id:"parked")],hasParachute=true
 var camera=SIMD3<Float>(12,34,56),objective:SIMD2<Float>?=SIMD2(1,2)
 let gameCamera=Camera();var gameCameraFrame:Int?=1,heading:Float=1.2,actorHeading:Float=0.3,cameraPitch:Float=0.2,cameraWasDriving=true
 var projectileRows=[1],reloadCancelled=false,resets=0
 let weaponEffects=Effects();var particleEffects:Effects?=Effects(),blasts=[1]
 var vehicleRigStates=["old":1],vehicleRigTimes=["old":1],vehicleRigSpins=["old":1]
 var remoteRiderPlayback=["old":1],remoteRiderActions=["old":1],remoteRiderCapture=["old":1],remoteRiderPrevious=["old":1],remoteRiderAnimations=["old":1]
 var remoteFootAnimations=["old":1],remoteBikeAnimations=["old":1],remoteBikeSamples=["old":1],remoteBikeFrames=["old":1]
 var flightCanopyPoses=["own":1],flightCanopyLanded=["own":1],flightAudioVoices=[1]
 var lastRiderDraw:Double=123,remoteServerTimeOffsetMilliseconds:Double?=456
 var riderPoseClock=Clock()
 func synchronizeProjectiles(_ rows:[Int]){projectileRows=rows}
 func cancelReloadAnimation(){reloadCancelled=true}
 func teleport(x:Float,y:Float,z:Float,direction:Float?=nil){camera=SIMD3(x,y,z);if let direction {self.heading=direction};resets+=1}
'''+method(renderer,'    func setVehicleCouplingConnection(')+method(renderer,'    private func discardOwnedVehicle()')+method(renderer,'    func revokeVehicleForServerPlacement()')+method(renderer,'    func revokePassenger(')+method(renderer,'    func deferVehicleExit(')+method(renderer,'    @discardableResult func removeVehicle(')+method(renderer,'    private func clearMultiplayerPresentation()')+method(renderer,'    func resetMultiplayerSession()')+r'''
}
struct RawKey:Hashable {let rawValue:Int}
final class Text {var text=""}
final class Button {func setTitle(_ title:String,for state:ButtonState){text=title};var text=""}
enum ButtonState {case normal}
final class Radar {var target:SIMD2<Float>?=SIMD2(1,2)}
final class HUD {let radar=Radar();var vehicle:String?="OLD";func updateVehicle(name:String?,speed:Float){vehicle=name}}
final class Gameplay {var ready=false,refreshes=0;func setConnectionReady(_ value:Bool){ready=value};func refresh(){precondition(ready);refreshes+=1}}
final class Network {var positionAcknowledgements=false;var onTeleport:((SIMD3<Float>,Float?)->Void)?;var passengerExitWrites=0;func sendPassengerExit(_ point:SIMD3<Float>,heading:Float){passengerExitWrites+=1};var legacy:AnyObject?;var stops=0,activities=[Bool]();func setApplicationActive(_ value:Bool){activities.append(value)};func disconnect(){stops+=1;ownerCalls.append("network-disconnect")}}
final class Audio {var stops=0,reloadCancels=0;func stop(){stops+=1};func cancelReload(){reloadCancels+=1}}
final class Display {var invalidated=false;func invalidate(){invalidated=true;ownerCalls.append("display-invalidate")}}
struct Clock {var resets=0;mutating func reset(){resets+=1}}
final class Presenter {var isBeingDismissed=false}
final class Handoff {var releases=0;func release(){releases+=1}}
final class LegacyDialog {var invalidations=0;func invalidate(){invalidations+=1}}
final class LegacyOverlay {var clears=0;func clear(){clears+=1}}
final class Artwork {
 static var cancelled:Set<UUID>=[]
 let id=UUID()
 func cancel(){Self.cancelled.insert(id);ownerCalls.append("artwork-cancel")}
 deinit{ownerCalls.append("artwork-release")}
}
class Parent {func viewWillDisappear(_ animated:Bool){}}
enum NativeMultiplayerClient {typealias ConnectionState=NativeConnectionRecovery.State}
final class Game:Parent {
 let idleOwner=UUID();var gameStopped=false
 var applicationActive=true,pauseEscapeHandoff:Handoff?=Handoff()
 var legacyClassSkin:Int?
 func updateLegacyClassAdmission(){}
 let originalEffects=NativeOriginalWorldEffects();var originalExitToken:UInt64?=17
 var legacyDialog:LegacyDialog?=LegacyDialog(),legacyOverlay:LegacyOverlay?=LegacyOverlay(),legacySelection=true
 var legacyArtwork:Artwork?=Artwork()
 let gameplay=Gameplay(),network=Network(),radio=Audio(),audio=Audio(),gameHUD=HUD(),players=Text(),vehicleButton=Button()
 var renderer:Renderer?=Renderer(),displayLink:Display?=Display()
 var currentVehicle:Int?=1,heldKeys:Set<RawKey>=[RawKey(rawValue:26)]
 var previousAudioPosition:SIMD3<Float>?=SIMD3(1,2,3),lastAutomaticCheckpoint=["old":Date()]
 var lastNetwork:Double=55,lastGameplay:Double=66,frameClock=Clock(),controlResets=0,drivingControls=true
 var isBeingDismissed=false,isMovingFromParent=false,presentingViewController:Presenter?=Presenter()
 func resetControls(){heldKeys=[];controlResets+=1}
 func setDrivingControls(_ value:Bool){drivingControls=value}
'''+ '\n func installPlacementCallback(){\n'+method(vc,'        network.onTeleport =')+'\n}\n'+method(vc,'    private func connectionChanged(')+method(vc,'    private func vehicleRemoved(')+method(vc,'    private func stopGame()')+method(vc,'    override func viewWillDisappear(')+method(vc,'    @objc private func applicationResigned()')+method(vc,'    @objc private func applicationReturned()')+r'''
}
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
NativeMenuKeyLatch.reset()
let game=Game(),oldPosition=game.renderer!.camera
NativeGameplayIdleTimer.shared.claim(game.idleOwner,active:true)
let oldDialog=game.legacyDialog!,oldOverlay=game.legacyOverlay!
var delayedExit=false;game.renderer!.pendingVehicleExit={delayedExit=true}
var delayedPlacement=false;game.renderer!.deferVehicleExit{delayedPlacement=true};let queuedPlacement=game.renderer!.pendingExitPlacement
_=game.originalEffects.light();game.originalEffects.whiff(random:{0.5})
game.connectionChanged(.reconnecting)
check(!game.originalEffects.burning && !game.originalEffects.coughing && game.originalExitToken==nil && game.renderer!.actorEffectResets==1,"loss retained original actor effects or deferred exit ownership")
check(game.renderer!.networkInterior==nil,"independent reconnect inherited legacy interior filter")
let legacyLoss=Game();legacyLoss.network.legacy=NSObject();legacyLoss.connectionChanged(.reconnecting)
check(legacyLoss.renderer!.networkInterior==0,"legacy reconnect did not reset interior to exterior until server state arrives")
check(game.legacyDialog==nil&&oldDialog.invalidations==1&&oldOverlay.clears==1 && !game.legacySelection,"old legacy dialog/textdraw input survives disconnect")
check(!game.gameplay.ready && game.currentVehicle==nil && !game.drivingControls,"loss clears gameplay/driver ownership")
check(game.renderer!.camera==oldPosition,"loss manufactured a car-exit offset")
check(!game.renderer!.driving && game.renderer!.currentVehicleID==nil && !game.renderer!.groundVehicle!.active,"old body is discarded before welcome")
check(game.renderer!.groundVehicle!.otherIDs.isEmpty && game.renderer!.groundVehicle!.clears==1,"old session retains promoted parked bodies")
check(game.renderer!.couplingConnection==nil && game.renderer!.couplingSnapshot==nil && game.renderer!.vehicleCoupling!.connection==nil,"old session coupling namespace/topology survives")
check(game.renderer!.vehicleCoupling!.owner==nil && !game.renderer!.groundVehicle!.workingTowed,"loss retains tow ownership or working state")
check(Array(ownerCalls.prefix(3))==["coupling-reset","coupling-owner","body-exit"],"joints/ownership must be revoked before body removal")
check(game.renderer!.pendingVehicleExit==nil && !delayedExit,"queued old rider exit survives")
queuedPlacement?();check(game.renderer!.pendingExitPlacement==nil && !delayedPlacement,"queued geometry exit survives disconnect")
check(game.renderer!.remotePlayers.isEmpty && game.renderer!.remoteVehicles.isEmpty && game.renderer!.projectileRows.isEmpty,"old remote/projectile world survives")
let world=game.renderer!
check(world.vehicleRigStates.isEmpty && world.vehicleRigTimes.isEmpty && world.vehicleRigSpins.isEmpty,"old vehicle presentation survives new peer")
check(world.remoteRiderPlayback.isEmpty && world.remoteRiderActions.isEmpty && world.remoteRiderCapture.isEmpty && world.remoteRiderPrevious.isEmpty && world.remoteRiderAnimations.isEmpty,"same-id rider reused an old session task/pose")
check(world.passengerSeat==nil && world.passengerFrame==nil && world.passengerAccumulator==0,"new peer retains old passenger authority/frame/timing")
check(world.remoteFootAnimations.isEmpty && world.remoteBikeAnimations.isEmpty && world.remoteBikeSamples.isEmpty && world.remoteBikeFrames.isEmpty,"same-id remote ped reused old animation samples")
check(world.flightCanopyPoses.isEmpty && world.flightCanopyLanded.isEmpty && world.flightAudioVoices.isEmpty,"own landed canopy or old flight audio survives new world")
check(world.lastRiderDraw==0 && world.remoteServerTimeOffsetMilliseconds==nil,"old animation/server clock survives")
check(world.riderPoseClock.resets>0,"old rider pose interval survives session reset")
check(world.weaponEffects.clears==1 && world.particleEffects!.clears==1 && world.blasts.isEmpty,"old fires, particles, stream or blasts survive new world")
check(world.gameCamera.shakeCancels==1,"old camera impact survives new peer")
check(!game.renderer!.hasParachute && !game.renderer!.personalFlight.worn && game.renderer!.reloadCancelled,"old equipment/reload state survives")
check(game.gameHUD.vehicle==nil && game.gameHUD.radar.target==nil && game.renderer!.objective==nil,"old HUD/objective survives")
check(game.previousAudioPosition==nil && game.lastAutomaticCheckpoint.isEmpty && game.radio.stops==1,"loss retains stale timing/effects")
check(game.audio.reloadCancels==1,"session replacement retained queued reload audio")
check(NativeMenuKeyLatch.isHeld(26),"held gameplay key replays after loss")
NativeMenuKeyLatch.release(26)
check(!NativeMenuKeyLatch.isHeld(26),"fresh release cannot rearm")
game.renderer!.teleport(x:1480,y:-1738,z:13)
let resets=game.renderer!.resets
let reloadCancels=game.audio.reloadCancels
game.connectionChanged(.ready)
check(game.audio.reloadCancels==reloadCancels,"ready/input refresh canceled a legitimate reload owner")
check(game.gameplay.ready && game.gameplay.refreshes==1 && game.lastNetwork==0 && game.lastGameplay==0,"ready does not refresh/rebase clocks")
check(game.renderer!.resets==resets && game.renderer!.camera==SIMD3(1480,-1738,13) && game.currentVehicle==nil,"ready resurrects old driver or moves fresh spawn")
game.viewWillDisappear(true)
check(systemIdleDisabled && !game.gameStopped,"temporary presentation released gameplay's display ownership")
check(game.network.stops==0 && !game.displayLink!.invalidated && game.gameplay.ready,"temporary fullscreen presentation stopped live world")
check(game.legacyArtwork != nil && game.renderer!.legacyWorldClears==0,"temporary fullscreen presentation disposed live artwork/world owners")
let exitingArtworkID=game.legacyArtwork!.id
weak var exitingArtwork=game.legacyArtwork
let shutdownStart=ownerCalls.count
game.isBeingDismissed=true;game.viewWillDisappear(true)
check(!systemIdleDisabled && game.gameStopped,"permanent game exit failed to restore the previous display policy")
check(game.network.stops==1 && game.displayLink!.invalidated && !game.gameplay.ready && game.audio.stops==1,"permanent exit did not dispose owners")
let shutdownCalls=Array(ownerCalls.dropFirst(shutdownStart))
check(Artwork.cancelled.contains(exitingArtworkID) && game.legacyArtwork==nil && exitingArtwork==nil,"permanent exit retained artwork or released it before cancellation")
check(game.renderer!.legacyWorldClears==1,"permanent exit omitted authored legacy world disposal")
check(shutdownCalls==["artwork-cancel","artwork-release","legacy-world-clear","display-invalidate","network-disconnect"],"actual shutdown must cancel artwork before releasing its owner and clear world before display/network disposal")
let gone=Game(),beforeGone=gone.renderer!.camera
gone.gameplay.setConnectionReady(true)
gone.vehicleRemoved("parked")
check(gone.renderer!.vehicleCoupling!.removed==["parked"],"parked deletion does not revoke its couplings")
check(gone.currentVehicle != nil && gone.renderer!.driving && gone.renderer!.groundVehicle!.active,"parked deletion revoked unrelated local driver")
check(gone.renderer!.groundVehicle!.otherIDs==["old-car"] && gone.renderer!.remoteVehicles.count==1,"explicit deletion failed to remove parked prediction")
check(gone.radio.stops==0 && gone.controlResets==0,"parked deletion reset local input/audio")
var despawnExit=false;gone.renderer!.deferVehicleExit{despawnExit=true};let despawnQueued=gone.renderer!.pendingExitPlacement
gone.vehicleRemoved("old-car")
despawnQueued?();check(!despawnExit && gone.renderer!.pendingExitPlacement==nil,"queued geometry exit survives owned despawn")
check(gone.renderer!.vehicleCoupling!.removed==["parked","old-car"] && gone.renderer!.vehicleCoupling!.owner==nil,"owned deletion leaves a coupling claim")
check(gone.currentVehicle==nil && !gone.renderer!.driving && gone.renderer!.currentVehicleID==nil,"despawn retained local ownership")
check(gone.renderer!.groundVehicle!.exits==1 && !gone.renderer!.groundVehicle!.active,"despawn retained owned body")
check(gone.renderer!.camera==beforeGone && gone.renderer!.actorHeading==Float(1.2),"despawn manufactured exit displacement or stale actor facing")
check(gone.renderer!.pendingVehicleExit==nil && gone.renderer!.ownRiderPlayback==nil,"despawn retained delayed rider task")
check(gone.renderer!.remotePlayers==[1] && gone.renderer!.projectileRows==[1] && gone.renderer!.hasParachute,"one despawn cleared unrelated live world")
check(gone.renderer!.weaponEffects.clears==0 && !gone.renderer!.remoteRiderAnimations.isEmpty,"single despawn cleared unrelated effects/animations")
check(gone.gameplay.ready && gone.network.stops==0 && gone.radio.stops==1 && gone.gameHUD.vehicle==nil && !gone.drivingControls,"despawn failed to retain connection/reset vehicle UI")
gone.vehicleRemoved("old-car")
check(gone.renderer!.groundVehicle!.exits==1 && gone.radio.stops==1,"repeated despawn repeated owned exit")
check(game.renderer!.localHitReaction.resets>0 && game.renderer!.footDeathKind==nil && game.renderer!.pendingFootHit==nil,"session reset retained old damage response")
let replacement=Game()
NativeGameplayIdleTimer.shared.claim(replacement.idleOwner,active:true)
game.stopGame()
check(systemIdleDisabled && game.gameStopped,"old controller's repeated shutdown released the replacement game's display ownership")
replacement.stopGame()
check(!systemIdleDisabled && replacement.gameStopped,"replacement shutdown lost the original display policy")
let lifecycle=Game()
NativeGameplayIdleTimer.shared.claim(lifecycle.idleOwner,active:true)
lifecycle.applicationResigned()
check(!systemIdleDisabled && !lifecycle.applicationActive && lifecycle.network.activities==[false],"actual resign hook did not suspend display/network activity")
check(lifecycle.pauseEscapeHandoff!.releases==1 && lifecycle.frameClock.resets==1 && lifecycle.renderer!.displayResets==1 && lifecycle.controlResets==1,"actual resign hook retained paused input or frame history")
lifecycle.applicationReturned()
check(systemIdleDisabled && lifecycle.applicationActive && lifecycle.network.activities==[false,true],"actual return hook did not reacquire foreground gameplay")
check(lifecycle.frameClock.resets==2 && lifecycle.renderer!.displayResets==2 && lifecycle.controlResets==2,"actual return hook retained suspended clocks or held input")
lifecycle.stopGame()
let stoppedClock=lifecycle.frameClock.resets,stoppedControls=lifecycle.controlResets
lifecycle.applicationReturned()
check(!systemIdleDisabled && lifecycle.gameStopped && lifecycle.network.activities==[false,true],"late application notification revived a permanently stopped game")
check(lifecycle.frameClock.resets==stoppedClock && lifecycle.controlResets==stoppedControls,"late return mutated a stopped game's input or clock")
let finalOwner=Game();NativeGameplayIdleTimer.shared.claim(finalOwner.idleOwner,active:true)
lifecycle.applicationResigned()
check(systemIdleDisabled,"old controller's actual resign hook cleared the current game's display ownership")
finalOwner.stopGame();check(!systemIdleDisabled,"final actual shutdown did not restore the original display policy")
for role in ["driver","passenger","foot"] {
 let placing=Game();placing.network.positionAcknowledgements=true;placing.installPlacementCallback()
 let world=placing.renderer!,otherIDs=placing.renderer!.groundVehicle!.otherIDs
 world.passengerSeat=role=="passenger" ? 1:nil;world.driving=role != "foot";world.groundVehicle!.active=role != "foot"
 let target=SIMD3<Float>(700,-800,30);placing.network.onTeleport?(target,Float(-1.25))
 check(placing.currentVehicle==nil && !placing.drivingControls && placing.gameHUD.vehicle==nil,"Strict TP retained \(role) HUD/control owner")
 check(!world.driving && world.currentVehicleID==nil && world.passengerSeat==nil && !world.groundVehicle!.active,"Strict TP retained \(role) physical owner")
 check(world.camera==target && world.heading == -1.25 && world.resets==1,"Strict TP applied an exit offset or repeated teleport")
 check(world.pendingVehicleExit==nil && world.pendingExitPlacement==nil && world.ownRiderAnimation==nil,"Strict TP retained pending rider placement")
 check(!world.vehicleHorn && !world.vehicleSiren && !world.vehicleHop && world.steeringInput==0 && world.vehicleWorkingControl==0,"Strict TP retained vehicle control effects")
 check(world.groundVehicle!.otherIDs==otherIDs && world.remoteVehicles.count==2,"Strict TP cleared unrelated parked/remote world")
 check(placing.network.passengerExitWrites==0 && placing.network.stops==0 && placing.radio.stops==1,"Strict TP manufactured a passenger exit or disconnected the server")
 check(placing.previousAudioPosition==nil && placing.controlResets==1,"Strict TP retained old motion/input history")
 check(placing.audio.reloadCancels==1,"Strict TP retained queued reload audio")
}
let legacyPlacement=Game();legacyPlacement.installPlacementCallback();legacyPlacement.network.onTeleport?(SIMD3(4,5,6),nil)
check(legacyPlacement.network.passengerExitWrites==1 && legacyPlacement.renderer!.camera==SIMD3(4,5,6),"Unnegotiated passenger correction policy changed")
print("PASS connection owners: \(checks) actual extracted controller/renderer lifecycle checks (non-UI spies)")
'''
with tempfile.TemporaryDirectory(prefix='zgta-connection-owners-') as directory:
 root=Path(directory);source=root/'main.swift';binary=root/'verify'
 source.write_text(inputs[paths[2]]+'\n'+inputs[paths[3]]+'\n'+inputs[paths[4]]+'\n'+inputs[paths[5]]+'\n'+code)
 subprocess.run(['xcrun','swiftc','-whole-module-optimization','-Onone','-num-threads','1','-module-cache-path',str(OUT/'modules'),str(source),'-o',str(binary)],check=True,timeout=900)
 result=subprocess.run([str(binary)],check=True,capture_output=True,text=True);print(result.stdout,end='')
 (OUT/'report.json').write_text(json.dumps({'pass':True,'output':result.stdout,'scope':__doc__,'sources':{p:hashlib.sha256(value.encode()).hexdigest() for p,value in inputs.items()}},indent=2)+'\n')
