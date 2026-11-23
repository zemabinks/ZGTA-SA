import Foundation
import simd
var checks=0
func check(_ c:@autoclosure()->Bool,_ m:String){checks+=1;if !c(){fatalError(m)}}
final class NativeAppSettings {static let shared=NativeAppSettings()}
class HarnessBase {init(nibName:String?,bundle:Bundle?){}}
protocol NativeLegacyWorldConnection:AnyObject {}
final class HarnessLegacy:NativeLegacyWorldConnection {}
struct HarnessPlayer {let id:String;let position:SIMD3<Float>;var passive=false;var life:Double=100;var code="s7";var ridingVehicleID:String?}
struct HarnessAmbient {let targetID:String;let position:SIMD3<Double>;let dead:Bool}
final class NativeMultiplayerClient {
 enum Flavor {case selfHost;case originalWorld(build:String,deviceID:String)}
 let server:ServerAddress,flavor:Flavor
 let legacy:NativeLegacyWorldConnection?
 var usesClientOwnedWeapons:Bool {if legacy != nil{return true};if case .originalWorld=flavor{return true};return false}
 var isReady=true,health=100,passive=false
 let sequence=NativeShotSequence();var reserves=0,detonations=0,resyncs=0
 var orderedPlayers:[HarnessPlayer]=[.init(id:"peer",position:SIMD3(0,10,0))]
 var inventoryConnection:String?{sequence.connection}
 struct Packet {let weapon:Int,origin:SIMD3<Float>,target:SIMD3<Float>,player:String?,ticket:NativeShotTicket?}
 var packets:[Packet]=[]
 init(server:ServerAddress,session:URLSession,flavor:Flavor,legacy:NativeLegacyWorldConnection?=nil){self.server=server;self.flavor=flavor;self.legacy=legacy}
 func reserveShot()->NativeShotTicket? {reserves+=1;guard isReady,health>0,!passive else{return nil};return sequence.reserve()}
 func detonateSatchels(){detonations+=1}
 func requestInventoryResync(){resyncs+=1}
 @discardableResult func sendWeaponShot(weapon:Int,from origin:SIMD3<Float>,to target:SIMD3<Float>,player:String?,ticket:NativeShotTicket?=nil,streamPlayers:[String]=[])->Bool {
  if !usesClientOwnedWeapons {guard let ticket,sequence.claim(ticket)else{return false}}
  packets.append(.init(weapon:weapon,origin:origin,target:target,player:player,ticket:ticket));return true
 }
 @discardableResult func sendOrdinaryShotBatch(weapon:Int,claims:[NativeLocalShots.Claim],ticket:NativeShotTicket?)->Bool {
  preconditionFailure("Ordinary resolver is covered by the separate actual local-shot dispatch gate")
 }
}
final class NativeGameplayClient {
 let server:ServerAddress;var calls=0,state:[String:Any]=[:]
 init(server:ServerAddress){self.server=server}
 func perform(_ action:String,payload:[String:Any]=[:],reportSuccess:Bool=true,completion:((Bool?)->Void)?=nil){calls+=1;completion?(false)}
}
final class NativeVehicleRadio {let server:ServerAddress;init(server:ServerAddress){self.server=server}}
final class NativeGameAudio {
 let server:ServerAddress;var shots=0,reloads=0,reloadCancels=0
 init(server:ServerAddress){self.server=server}
 func shot(weapon:Int){shots+=1}
 func reload(weapon:Int){reloads+=1}
 func cancelReload(){reloadCancels+=1}
}
final class NativeWorldRenderer {
 var presentedRemotePlayers:[HarnessPlayer]=[.init(id:"peer",position:SIMD3(0,10,0))]
 var remotePlayers:[HarnessPlayer]{presentedRemotePlayers}
 // ACTUAL_PASSIVE_ADMISSION
 var presentedAmbientPedestrians:[HarnessAmbient]=[]
 struct Muzzle {let origin:SIMD3<Float>,safetyOrigin:SIMD3<Float>}
 var swimming=false,isChuting=false,isClimbing=false,crouching=false
 var hasNativeFootWeaponTiming=true,canEmitFootWeaponShot=true,weaponReady=false
 var muzzleAvailable=true,clear=true
 var aimDirection=SIMD3<Float>(0,1,0)
 var records=0,cancels=0,reloadCancels=0,fireStarts=0
 func weaponMuzzle(weapon:Int,left:Bool)->Muzzle? {
  guard muzzleAvailable else{return nil};let p=SIMD3<Float>(left ? -0.15:0.15,0,1)
  return .init(origin:p,safetyOrigin:p)
 }
 func hasClearShot(from:SIMD3<Float>,to:SIMD3<Float>)->Bool{clear}
 func captureLocalShot(weapon:Int,left:Bool,range:Float,pellets:Int,accuracy:Double,damage:Double,muzzle:Muzzle,barrelClear:Bool)->NativeLocalShots.Input?{nil}
 func resolveLocalShot(_ input:NativeLocalShots.Input)->NativeLocalShots.Frame?{preconditionFailure("Separate local-shot gate")}
 func presentLocalShot(_ frame:NativeLocalShots.Frame,input:NativeLocalShots.Input,left:Bool,beforePellets:()->Void){preconditionFailure("Separate local-shot gate")}
 func recordWeaponShot(weapon:Int,origin:SIMD3<Float>,direction:SIMD3<Float>){records+=1}
 func cancelWeaponInput(){cancels+=1}
 func cancelReloadAnimation(){reloadCancels+=1}
 func fireWeapon(clip:String,duration:Double){fireStarts+=1}
}
final class Status {var text=""}
final class Game:HarnessBase {
 let server:ServerAddress,appSettings:NativeAppSettings,network:NativeMultiplayerClient,gameplay:NativeGameplayClient,radio:NativeVehicleRadio,audio:NativeGameAudio
 var weapons:NativeWeaponState,renderer:NativeWorldRenderer?
 var applicationActive=true,presentedViewController:Int?,currentVehicle:Int?,aiming=false
 var weaponCycle=NativeWeaponCycleQueue(),acceptsHeldInput=true,updates=0
 let status=Status()
 var usingPistol:Bool{weapons.current.isGun}
 var magazine:Int{weapons.rounds};var reserve:Int{weapons.reserve}
 func updateWeaponHUD(){updates+=1}
 // ACTUAL_CONSTRUCTOR
 // ACTUAL_METHODS
}
let assets=ServerAddress("http://127.0.0.1:1")!,world=ServerAddress("http://127.0.0.1:2")!
var clock=0.0
let defs:[NativeOriginalWorldArsenal.Definition]=[
 .init(id:22,slot:2,capacity:17,kind:"INSTANT_HIT",wait:0,reload:1),
 .init(id:31,slot:5,capacity:50,kind:"INSTANT_HIT",wait:0,reload:1)]
let catalog:[NativeWeaponState.Weapon]=[
 .init(id:22,name:"Fixture",model:"",range:40,capacity:17,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT"),
 .init(id:31,name:"Fixture2",model:"",range:40,capacity:50,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT")]
func game(_ original:Bool,legacy:Bool=false)->Game {
 let flavor:NativeMultiplayerClient.Flavor=original ? .originalWorld(build:"202611100434",deviceID:String(repeating:"a",count:32)):.selfHost
 let legacyConnection:NativeLegacyWorldConnection?=legacy ? HarnessLegacy():nil
 let game=Game(server:assets,networkServer:world,flavor:flavor,legacy:legacyConnection)
 check(game.weapons.policy==(legacy ? .legacySAMP:original ? .originalWorld:.acknowledgedSelfHost),"Actual constructor selects explicit inventory owner")
 check(game.server.url==assets.url&&game.radio.server.url==assets.url&&game.audio.server.url==assets.url,"Actual constructor retains local native asset origin")
 check(game.network.server.url==world.url&&game.gameplay.server.url==world.url,"Actual constructor uses separate network destination")
 game.weapons=NativeWeaponState(catalog:catalog,policy:legacy ? .legacySAMP:original ? .originalWorld:.acknowledgedSelfHost,originalDefinitions:defs,clock:{clock})
 if legacy {check(game.network.legacy === legacyConnection,"Actual constructor retains supplied legacy transport")}
 if legacy {game.weapons.setClientWeaponReady(true);_=game.weapons.giveClientWeapon(22,amount:20);_=game.weapons.giveClientWeapon(31,amount:80);_=game.weapons.selectOriginalWeapon(22)}
 else if original {_=game.weapons.applyOriginalGuns([[22,20],[31,80]]);_=game.weapons.selectOriginalWeapon(22)}
 else {
  _=game.network.sequence.negotiate("fixture");game.weapons.setConnection("fixture")
  check(game.weapons.apply(["revision":0,"selected":22,"weapons":[["id":22,"clip":17,"rest":3]],"ack":["connection":"fixture","processedShot":0]]),"Real acknowledged default baseline")
 }
 return game
}
for (original,legacy) in [(true,false),(false,false),(false,true)]{
 let clientOwned=original||legacy
 let g=game(original,legacy:legacy);let before=g.weapons.rounds
 check(g.consumeFootWeaponShot(weapon:22,left:false),"Actual controller emission accepted")
 check(g.weapons.rounds==before-1&&g.renderer!.records==1&&g.network.packets.count==1,"One consumed round, recorded effect and network emission")
 check(g.network.reserves==(clientOwned ? 0:1),"Only strict selfhost reserves a ticket")
 check((g.network.packets[0].ticket==nil)==clientOwned,"No forged ticket in original controller path")
 check(g.network.packets[0].origin==SIMD3(0.15,0,1),"Actual event-time right-hand muzzle")
 check(g.consumeFootWeaponShot(weapon:22,left:true),"Actual left-hand emission")
 check(g.network.packets[1].origin==SIMD3(-0.15,0,1),"Actual event-time left-hand muzzle retained")
 let after=g.weapons.rounds;g.renderer!.muzzleAvailable=false
 check(!g.consumeFootWeaponShot(weapon:22,left:false)&&g.weapons.rounds==after&&g.network.packets.count==2,"Missing muzzle neither spends nor emits")
}
for guardName in ["background","overlay","vehicle","cycle","dead","passive","swim","chute","timing","selected","pose"]{
 let g=game(true)
 switch guardName {
 case"background":g.applicationActive=false
 case"overlay":g.presentedViewController=1
 case"vehicle":g.currentVehicle=1
 case"cycle":_=g.weaponCycle.request(direction:1,owned:[0,22,31],selected:22)
 case"dead":g.network.health=0
 case"passive":g.network.passive=true
 case"swim":g.renderer!.swimming=true
 case"chute":g.renderer!.isChuting=true
 case"timing":g.renderer!.hasNativeFootWeaponTiming=false
 case"selected":_=g.weapons.selectOriginalWeapon(31)
 case"pose":g.renderer!.canEmitFootWeaponShot=false
 default:break
 }
 let count=g.weapons.rounds;check(!g.consumeFootWeaponShot(weapon:22,left:false)&&g.weapons.rounds==count&&g.network.packets.isEmpty,"Controller guard\(guardName)")
}
let original=game(true);_=original.consumeFootWeaponShot(weapon:22,left:false)
original.reload();check(original.gameplay.calls==0&&original.weapons.reloading&&original.audio.reloads==1&&original.renderer!.cancels==1,"Original reload is local and cannot hit independent HTTP")
let before=original.weapons.rounds;check(!original.consumeFootWeaponShot(weapon:22,left:false)&&original.weapons.rounds==before,"Reload owns original muzzle boundary")
clock=1.1;original.weapons.tick();check(original.consumeFootWeaponShot(weapon:22,left:false),"Original controller resumes after local reload deadline")
original.cycleWeapon(1);check(original.weapons.selected==31&&original.gameplay.calls==0,"Original actual cycle selects owned next slot without HTTP")
let strict=game(false);_=strict.consumeFootWeaponShot(weapon:22,left:false)
strict.reload();check(strict.gameplay.calls==1&&!strict.weapons.reloading&&strict.renderer!.fireStarts==0 && strict.audio.reloadCancels==1,"Strict original-independent HTTP reload rejection retained")
strict.cycleWeapon(1);check(strict.gameplay.calls==2,"Strict cycle still uses independent server authority")
let noAuthority=game(false);noAuthority.weapons.setConnection(nil)
check(!noAuthority.consumeFootWeaponShot(weapon:22,left:false)&&noAuthority.network.packets.isEmpty,"Strict controller cannot use original no-ticket path")
let legacyGame=game(false,legacy:true);_=legacyGame.consumeFootWeaponShot(weapon:22,left:false)
legacyGame.reload();check(legacyGame.gameplay.calls==0&&legacyGame.weapons.reloading,"Legacy reload stays in actual client-owned controller path")
clock+=1.1;legacyGame.weapons.tick();legacyGame.cycleWeapon(1)
check(legacyGame.weapons.selected==31&&legacyGame.gameplay.calls==0,"Legacy actual controller cycles without original/selfhost HTTP protocol")
for (original,legacy) in [(true,false),(false,true),(false,false)] {
 for (weapon,kind) in [(22,"INSTANT_HIT"),(16,"PROJECTILE")] {
  let g=game(original,legacy:legacy)
  let policy:NativeWeaponState.Policy=legacy ? .legacySAMP:original ? .originalWorld:.acknowledgedSelfHost
  g.weapons=NativeWeaponState(catalog:[.init(id:weapon,name:"One round",model:"",range:40,capacity:1,interval:0.1,animation:"fixture",fireKind:kind)],policy:policy,originalDefinitions:[.init(id:weapon,slot:2,capacity:1,kind:kind,wait:0,reload:1)],clock:{clock})
  if original {_=g.weapons.applyOriginalGuns([[weapon,1]]);_=g.weapons.selectOriginalWeapon(weapon)}
  else if legacy {g.weapons.setClientWeaponReady(true);_=g.weapons.giveClientWeapon(weapon,amount:1)}
  else {g.weapons.setConnection("fixture");_=g.weapons.apply(["revision":0,"selected":weapon,"weapons":[["id":weapon,"clip":1,"rest":0]],"ack":["connection":"fixture","processedShot":0]])}
  check(g.consumeFootWeaponShot(weapon:weapon,left:false),"final original/legacy/default round accepted")
  check(g.network.packets.count==1&&g.network.packets[0].weapon==weapon&&g.renderer!.records==1,"accepted last round keeps event-time weapon despite automatic holster")
  check(g.audio.shots==(kind=="PROJECTILE" ? 0:1),"last round retains event-time fire kind")
  check(!g.consumeFootWeaponShot(weapon:weapon,left:true)&&g.network.packets.count==1,"second hand cannot duplicate the exhausted final round")
  if kind=="PROJECTILE" {check(g.network.packets[0].player==nil&&g.network.packets[0].target==SIMD3(0.15,40,1),"last projectile retains launch path")}
 }
}
let shotgunInventory=NativeWeaponState(catalog:[.init(id:25,name:"Authored pellet gate",model:"",range:35,capacity:1,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT",pellets:15)],
 policy:.originalWorld,originalDefinitions:[.init(id:25,slot:3,capacity:1,kind:"INSTANT_HIT",wait:0,reload:1)],clock:{clock})
check(shotgunInventory.applyOriginalGuns([[25,15]]) && shotgunInventory.selectOriginalWeapon(25),"Authored owned shotgun admitted")
let beforePelletAmmo=shotgunInventory.rounds+shotgunInventory.reserve
let pelletInput=NativeLocalShots.Input(weapon:25,range:35,pellets:15,accuracy:1,damage:10,feet:.zero,heading:0,crouched:false,
 camera:SIMD3(0,-3,1.6),forward:SIMD3(0,1,0),up:SIMD3(0,0,1),verticalFov:55,aspect:2,muzzle:SIMD3(0,0,1.6),hipOrigin:SIMD3(0,0,1.6),scoped:false,hip:true,milliseconds:250)
var pelletEmissions=0,pelletCount=0,publishedPelletReady=true
check(NativeWeaponShotDelivery.deliver(weapon:25,left:false,inventory:shotgunInventory,readiness:{publishedPelletReady=$0},emission:{_,_ in
 pelletEmissions+=1
 pelletCount=NativeLocalShots(random:{0.5}).fire(pelletInput,people:[],world:{_ in .clear})!.pellets.count
}),"One real inventory/marker delivery resolves shotgun pellets")
check(pelletEmissions==1 && pelletCount==15 && beforePelletAmmo-shotgunInventory.rounds-shotgunInventory.reserve==1,"Fifteen resolved pellets spend exactly one real arsenal round")
check(!publishedPelletReady,"Exhausted one-round clip readiness published before emission")
print("PASS actual GameVC original/self-host/legacy controller dispatch: \(checks) checks")
