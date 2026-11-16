import Foundation
import simd
var checks=0
func check(_ value:Bool,_ name:String){checks+=1;guard value else{fatalError("Original gameplay: "+name)}}
func close(_ a:Double,_ b:Double)->Bool{abs(a-b)<0.000001}
final class NetworkCarrier {
 let vitals=NativeOriginalWorldVitals();var usesOriginalWorldProtocol=true,isReady=true,now=0.0
 var health:Int{vitals.displayHealth};var originalHealth:Double{vitals.health};var originalArmour:Double{vitals.armour}
 var originalFatal:NativeOriginalWorldVitals.PendingFatal?{vitals.pendingFatal}
 var cash=123,localSkin=7,clears=0,respawns=0,applications=0
 var onResult:((NativeOriginalWorldVitals.Result,NativeOriginalWorldVitals.Hit)->Void)?
 @discardableResult func applyOriginalDamage(_ hit:NativeOriginalWorldVitals.Hit,context:NativeOriginalWorldVitals.Context = .init())->NativeOriginalWorldVitals.Result{applications+=1;let result=vitals.hurt(hit,context:context);onResult?(result,hit);return result}
 @discardableResult func deferOriginalFatal(_ hit:NativeOriginalWorldVitals.Hit,drivingCar:Bool,speed:Double)->Bool{vitals.deferMovingCarFatal(hit,nowMilliseconds:now,drivingCar:drivingCar,speed:speed) != nil}
 @discardableResult func deferOriginalImmediateFatal(_ hit:NativeOriginalWorldVitals.Hit)->Bool{vitals.deferNativeExitFatal(hit,nowMilliseconds:now) != nil}
 @discardableResult func deferOriginalSelfKill(drivingCar:Bool,speed:Double)->Bool{vitals.deferMovingCarSelfKill(nowMilliseconds:now,drivingCar:drivingCar,speed:speed) != nil}
 @discardableResult func deferOriginalImmediateSelfKill()->Bool{vitals.deferNativeExitSelfKill(nowMilliseconds:now) != nil}
 func readyOriginalFatal(driving:Bool,wrecked:Bool)->NativeOriginalWorldVitals.PendingFatal?{vitals.readyFatal(nowMilliseconds:now,driving:driving,wrecked:wrecked)}
 @discardableResult func commitOriginalFatal(_ token:UInt64)->Bool{guard isReady,let cause=vitals.consumeFatal(token:token)else{return false};switch cause{case .selfKill:killOriginalPlayer();case .hit(let hit):_=applyOriginalDamage(hit)};return true}
 func setOriginalHealth(_ value:Double){_=vitals.setHealth(value)}
 func setOriginalArmour(_ value:Double){_=vitals.setArmour(value)}
 func setLocalSkin(_ value:Int){localSkin=value}
 func killOriginalPlayer(){vitals.kill()}
 func cancelOriginalFatal(){vitals.cancelPendingFatal()}
 func clearOriginalChat(){clears+=1}
 func respawnOriginalPlayer(){respawns+=1;vitals.respawn()}
}
final class RendererCarrier {
 var vehicleKind="car",drivingSpeed:Float=1,vehicleHealth=1000,cameraDirection:Float=0.7
 var swimming=false,underwater=false,parry=false,hasOriginalWorldFire=false,hasOriginalWorldGas=false
 var originalCoughing=false,burning=false,jetpack=false,parachute=false,localSkin=7,repairs=0,flips=0,cancels=0,abandons=0
 var lifted=0.0,point=SIMD3<Float>.zero,facing:Float?,dayShift=0.0,dayHold:Double?,weather:Int?
 func canParryOriginalHit(_ hit:NativeOriginalWorldVitals.Hit)->Bool{parry}
 func setFlightGear(parachute:Bool,jetpack:Bool){self.parachute=parachute;self.jetpack=jetpack}
 @discardableResult func setLocalSkin(_ id:Int)->Bool{localSkin=id;return true}
 @discardableResult func repairOriginalVehicle()->Bool{repairs+=1;return true}
 @discardableResult func flipOriginalVehicle()->Bool{flips+=1;return true}
 func liftOriginalPlayer(_ value:Double){lifted=value}
 func leaveVehicleForOriginalTeleport(){abandons+=1}
 func teleport(x:Float,y:Float,z:Float,direction:Float?){point=SIMD3(x,y,z);facing=direction}
 func setWeatherOverride(_ id:Int?){weather=id}
 func cancelWeaponInput(){cancels+=1}
 func setOriginalActorEffects(burning:Bool,coughing:Bool){self.burning=burning;originalCoughing=coughing}
}
final class ArsenalCarrier {
 struct Item{let id:Int};var weapons=[Item(id:46)],staffCalls=0,lastAlive:Bool?
 @discardableResult func applyOriginalStaffWeapons(_ packet:[String:Any],alive:Bool)->Bool{staffCalls+=1;lastAlive=alive;return true}
}
struct VehicleCarrier{let id:String}
final class HUDCarrier {var cash=0;func updateCash(_ value:Int){cash=value};func updateVehicle(name:String?,speed:Float){}}
enum StateCarrier{case normal}
final class ButtonCarrier {func setTitle(_ value:String,for state:StateCarrier){}}
final class StatusCarrier {var text=""}
final class RadioCarrier {var stops=0;func stop(){stops+=1}}
final class Game {
 let network=NetworkCarrier(),weapons=ArsenalCarrier(),gameHUD=HUDCarrier(),vehicleButton=ButtonCarrier(),status=StatusCarrier(),radio=RadioCarrier()
 var renderer:RendererCarrier?=RendererCarrier(),currentVehicle:VehicleCarrier?,originalExitToken:UInt64?
 let originalEffects=NativeOriginalWorldEffects()
 var resets=0,exitCalls=0,exitReady=false,drivingControls=false
 var pendingExit:(()->Void)?
 func resetControls(){resets+=1}
 func setDrivingControls(_ value:Bool){drivingControls=value}
 func completeVehicleExit(afterExit:(()->Void)?=nil){exitCalls+=1;if exitReady{currentVehicle=nil;afterExit?()}else{pendingExit=afterExit}}
 func finishExit(){currentVehicle=nil;let done=pendingExit;pendingExit=nil;done?()}
 func hit(_ value:NativeOriginalWorldVitals.Hit){receiveOriginalHit(value)}
 func frame(_ steps:[Double]){stepOriginalGameplay(steps)}
 func process(){processOriginalFatal()}
 func command(_ packet:[String:Any]){for event in NativeOriginalWorldCommands.decode(packet){receiveOriginalEvent(event,packet:packet)}}
 init(){network.onResult={[weak self] result,hit in guard let self else{return};if result.startBurning{_=self.originalEffects.light(by:hit.source)};if result.startGas{self.originalEffects.whiff(by:hit.source,random:{0.5})};if result.douse{self.originalEffects.douse(0.3)}}}
 // ACTUAL_METHODS
}
for kind in ["car","bike","boat"]{for speed in [Float(0.5),0.5001,-1]{
 let game=Game();game.currentVehicle=VehicleCarrier(id:"owned");game.renderer!.vehicleKind=kind;game.renderer!.drivingSpeed=speed
 _=game.network.vitals.begin(health:10,armour:0);game.hit(.init(damage:20,weapon:22,source:"peer"))
 let moving=kind=="car" && abs(speed)>0.5
 check(game.network.originalFatal?.untilMilliseconds==(moving ? 2000:0),"source moving-car threshold versus immediate native exit")
 check(game.network.originalHealth==10 && game.network.applications==0,"fatal hit waits for actual exit")
 game.hit(.init(damage:5,weapon:22));check(game.network.originalHealth==10 && game.network.applications==0,"seated pending fatal suppresses further hits")
 game.network.now=1999;game.process();check(game.exitCalls==(moving ? 0:1),"strict two-second deadline for moving car only")
 game.network.now=2000;game.process();let count=game.exitCalls;game.process();check(game.exitCalls==count && count==1,"queued geometry exit is requested once")
 game.network.setOriginalHealth(100);game.finishExit()
 check(game.currentVehicle==nil && game.network.originalHealth==80 && game.network.applications==1 && game.network.originalFatal==nil,"accepted real exit commits once and keeps staff heal during delay")
}}
do{
 let game=Game();game.currentVehicle=VehicleCarrier(id:"owned");_=game.network.vitals.begin(health:10,armour:0)
 game.hit(.init(damage:20,weapon:22));game.network.now=2000;game.process();let stale=game.pendingExit
 game.network.respawnOriginalPlayer();stale?();check(game.network.originalHealth==10 && game.network.applications==0,"living reset invalidates old exit identity without invented healing")
}
do{
 let game=Game();game.renderer!.parry=true
 game.hit(.init(damage:10,weapon:0,point:SIMD3(0,1,0)));check(game.network.originalHealth==100,"real parry context reaches fractional owner")
 game.hit(.init(damage:0.1,weapon:22));check(close(game.network.originalHealth,99.9),"gun cannot become melee block")
 game.hit(.init(damage:5,weapon:37,source:"burner"));check(close(game.network.originalHealth,99.9)&&game.originalEffects.burning,"flame hit starts actual timer without immediate health loss")
 game.frame(Array(repeating:1/60,count:180));check(close(game.network.originalHealth,99.9-2.333*8.25) && !game.originalEffects.burning,"all actor fire damage is fractional and expires")
}
do{
 let game=Game();game.hit(.init(damage:0.2,weapon:41));check(close(game.network.originalHealth,99.8)&&game.originalEffects.coughing,"spray damages once and starts cough")
 game.frame(Array(repeating:0.1,count:20));check(close(game.network.originalHealth,99.8) && !game.renderer!.originalCoughing,"spray cough adds no volume damage and releases controls")
 game.renderer!.hasOriginalWorldFire=true;game.frame([1.0/60]);game.renderer!.hasOriginalWorldFire=false;check(game.originalEffects.burning,"actual world volume starts timer")
 game.renderer!.swimming=true;game.frame([1.0/60]);check(!game.originalEffects.burning,"entering water extinguishes actor")
}
do{
 let game=Game();game.command(["t":"staff","hp":42.25,"armour":11.15,"freeze":true,"jetpack":true,"skin":264,"clear":true,"give":[22,50]])
 check(close(game.network.originalHealth,42.25) && close(game.network.originalArmour,11.15),"absolute staff setters retain fractions")
 check(game.resets==1 && game.weapons.staffCalls==1 && game.weapons.lastAlive==true,"freeze and actual arsenal dispatch use existing owners")
 check(game.renderer!.jetpack&&game.renderer!.parachute&&game.renderer!.localSkin==264&&game.network.localSkin==264,"staff gear/skin updates actual presentation owners")
 check(game.network.clears==1,"staff clear uses chat owner")
 game.currentVehicle=VehicleCarrier(id:"owned");game.command(["t":"tp","x":1,"y":2,"z":3,"h":90])
 check(game.currentVehicle==nil && game.renderer!.point==SIMD3(1,2,3) && close(Double(game.renderer!.facing!),-.pi/2),"original tp degrees are converted once and vehicle ownership is discarded")
 game.command(["t":"tp","x":4,"y":5,"z":6]);check(game.renderer!.facing==game.renderer!.cameraDirection,"missing tp.h adopts current native camera yaw")
 game.command(["t":"fix"]);game.command(["t":"flip"]);game.command(["t":"slap","h":102]);check(game.renderer!.repairs==1&&game.renderer!.flips==1&&game.renderer!.lifted==100,"vehicle commands route to real owner APIs")
 game.command(["t":"dose","heal":0.25]);check(close(game.network.originalHealth,42.5),"on-foot dose heals exact fraction")
 game.command(["t":"staff","respawn":true]);check(game.network.originalHealth==42.5&&game.network.originalArmour==11.15,"living staff respawn does not heal")
 game.command(["t":"day","shift":12,"hold":22]);check(game.renderer!.dayShift==12&&game.renderer!.dayHold==22,"day/hold are applied")
 game.command(["t":"weather","w":8]);check(game.renderer!.weather==8,"weather override applied")
 game.command(["t":"weather","w":-1]);check(game.renderer!.weather==nil,"weather clear returns to regional owner")
 game.command(["t":"cash","cash":123]);check(game.gameHUD.cash==123,"cash HUD uses active network authority")
 game.command(["t":"profile","name":"other"]);check(game.network.localSkin==264,"profile request never renames own player")
 game.network.usesOriginalWorldProtocol=false;game.command(["t":"staff","hp":1]);check(game.network.originalHealth==42.5,"original handlers do not mutate independent server")
}
print("PASS actual original GameVC ownership: \(checks) checks; typed commands, fractional effects, fatal-car delay/actual-exit handoff and stale identities")
