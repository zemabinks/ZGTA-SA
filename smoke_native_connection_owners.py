#!/usr/bin/env python3
"""Exercise actual extracted reconnect owner methods with non-UI owner spies.

Transport/HTTP/Rapier behavior has separate real-runtime gates. This checks
controller call ordering, retained pose, discarded ownership and modal lifetime.
"""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/connection-owners';OUT.mkdir(parents=True,exist_ok=True)
paths=['ios/App/NativeGameViewController.swift','ios/App/NativeWorldRenderer.swift','ios/App/NativeGameBindings.swift','ios/App/NativeConnectionRecovery.swift']
inputs={p:(ROOT/p).read_text() for p in paths}
def method(source,marker):
 start=source.index(marker);brace=source.index('{',start);depth=1;end=brace+1
 while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end].replace('private ','')+'\n'
vc,renderer=inputs[paths[0]],inputs[paths[1]]
code=r'''
import Foundation
import simd
final class Body {var active=true;var exits=0;func exit(){active=false;exits+=1}}
final class Flight {var worn=true;func wear(_ value:Bool){worn=value}}
final class Renderer {
 let groundVehicle:Body?=Body(),personalFlight=Flight()
 var driving=true,currentVehicleID:String?="old-car",drivingSpeed:Float=25,flightVerticalSpeed:Float=4
 var vehiclePitch:Float=0.2,vehicleFallbackRoll:Float=0.1,activeModelOrigin:Float=1
 var pendingVehicleBodyPose:Int?=1,activeVehicleModel="410",activeHandling:Int?=1,vehicleKind="car"
 var pendingVehicleExit:(()->Void)?={},ownRiderPlayback:Int?=1,ownRiderPrevious:Int?=1,ownRiderCapture:Int?=1,ownRiderFeet:Int?=1
 var riderDoorHolds=["old-car":1],remotePlayers=[1],remoteVehicles=[2],hasParachute=true
 var camera=SIMD3<Float>(12,34,56),objective:SIMD2<Float>?=SIMD2(1,2)
 var projectileRows=[1],reloadCancelled=false,resets=0
 func synchronizeProjectiles(_ rows:[Int]){projectileRows=rows}
 func cancelReloadAnimation(){reloadCancelled=true}
 func teleport(x:Float,y:Float,z:Float){camera=SIMD3(x,y,z);resets+=1}
'''+method(renderer,'    func resetMultiplayerSession()')+r'''
}
struct RawKey:Hashable {let rawValue:Int}
final class Text {var text=""}
final class Button {func setTitle(_ title:String,for state:ButtonState){text=title};var text=""}
enum ButtonState {case normal}
final class Radar {var target:SIMD2<Float>?=SIMD2(1,2)}
final class HUD {let radar=Radar();var vehicle:String?="OLD";func updateVehicle(name:String?,speed:Float){vehicle=name}}
final class Gameplay {var ready=false,refreshes=0;func setConnectionReady(_ value:Bool){ready=value};func refresh(){precondition(ready);refreshes+=1}}
final class Network {var stops=0;func disconnect(){stops+=1}}
final class Audio {var stops=0;func stop(){stops+=1}}
final class Display {var invalidated=false;func invalidate(){invalidated=true}}
struct Clock {var resets=0;mutating func reset(){resets+=1}}
final class Presenter {var isBeingDismissed=false}
class Parent {func viewWillDisappear(_ animated:Bool){}}
enum NativeMultiplayerClient {typealias ConnectionState=NativeConnectionRecovery.State}
final class Game:Parent {
 let gameplay=Gameplay(),network=Network(),radio=Audio(),audio=Audio(),gameHUD=HUD(),players=Text(),vehicleButton=Button()
 var renderer:Renderer?=Renderer(),displayLink:Display?=Display()
 var currentVehicle:Int?=1,heldKeys:Set<RawKey>=[RawKey(rawValue:26)]
 var previousAudioPosition:SIMD3<Float>?=SIMD3(1,2,3),lastAutomaticCheckpoint=["old":Date()]
 var lastNetwork:Double=55,lastGameplay:Double=66,frameClock=Clock(),controlResets=0,drivingControls=true
 var isBeingDismissed=false,isMovingFromParent=false,presentingViewController:Presenter?=Presenter()
 func resetControls(){heldKeys=[];controlResets+=1}
 func setDrivingControls(_ value:Bool){drivingControls=value}
'''+method(vc,'    private func connectionChanged(')+method(vc,'    private func stopGame()')+method(vc,'    override func viewWillDisappear(')+r'''
}
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
NativeMenuKeyLatch.reset()
let game=Game(),oldPosition=game.renderer!.camera
var delayedExit=false;game.renderer!.pendingVehicleExit={delayedExit=true}
game.connectionChanged(.reconnecting)
check(!game.gameplay.ready && game.currentVehicle==nil && !game.drivingControls,"loss clears gameplay/driver ownership")
check(game.renderer!.camera==oldPosition,"loss manufactured a car-exit offset")
check(!game.renderer!.driving && game.renderer!.currentVehicleID==nil && !game.renderer!.groundVehicle!.active,"old body is discarded before welcome")
check(game.renderer!.pendingVehicleExit==nil && !delayedExit,"queued old rider exit survives")
check(game.renderer!.remotePlayers.isEmpty && game.renderer!.remoteVehicles.isEmpty && game.renderer!.projectileRows.isEmpty,"old remote/projectile world survives")
check(!game.renderer!.hasParachute && !game.renderer!.personalFlight.worn && game.renderer!.reloadCancelled,"old equipment/reload state survives")
check(game.gameHUD.vehicle==nil && game.gameHUD.radar.target==nil && game.renderer!.objective==nil,"old HUD/objective survives")
check(game.previousAudioPosition==nil && game.lastAutomaticCheckpoint.isEmpty && game.radio.stops==1,"loss retains stale timing/effects")
check(NativeMenuKeyLatch.isHeld(26),"held gameplay key replays after loss")
NativeMenuKeyLatch.release(26)
check(!NativeMenuKeyLatch.isHeld(26),"fresh release cannot rearm")
game.renderer!.teleport(x:1480,y:-1738,z:13)
let resets=game.renderer!.resets
game.connectionChanged(.ready)
check(game.gameplay.ready && game.gameplay.refreshes==1 && game.lastNetwork==0 && game.lastGameplay==0,"ready does not refresh/rebase clocks")
check(game.renderer!.resets==resets && game.renderer!.camera==SIMD3(1480,-1738,13) && game.currentVehicle==nil,"ready resurrects old driver or moves fresh spawn")
game.viewWillDisappear(true)
check(game.network.stops==0 && !game.displayLink!.invalidated && game.gameplay.ready,"temporary fullscreen presentation stopped live world")
game.isBeingDismissed=true;game.viewWillDisappear(true)
check(game.network.stops==1 && game.displayLink!.invalidated && !game.gameplay.ready && game.audio.stops==1,"permanent exit did not dispose owners")
print("PASS connection owners: \(checks) actual extracted controller/renderer lifecycle checks (non-UI spies)")
'''
with tempfile.TemporaryDirectory(prefix='zgta-connection-owners-') as directory:
 root=Path(directory);source=root/'main.swift';binary=root/'verify'
 source.write_text(inputs[paths[2]]+'\n'+inputs[paths[3]]+'\n'+code)
 subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),str(source),'-o',str(binary)],check=True)
 result=subprocess.run([str(binary)],check=True,capture_output=True,text=True);print(result.stdout,end='')
 (OUT/'report.json').write_text(json.dumps({'pass':True,'output':result.stdout,'scope':__doc__,'sources':{p:hashlib.sha256(value.encode()).hexdigest() for p,value in inputs.items()}},indent=2)+'\n')
