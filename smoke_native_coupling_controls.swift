enum ControlState {case normal}
struct UIColor {static let black=UIColor();func withAlphaComponent(_ value:Double)->UIColor{self}}
final class Button {var isHidden=false,title="",accessibilityLabel="",backgroundColor=UIColor.black;func setTitle(_ text:String,for state:ControlState){title=text}}
final class Status {var text=""}
final class HUD {func updateVehicle(name:String?,speed:Float){}}
final class Radio {var stops=0;func stop(){stops+=1}}
final class Gameplay {var inventoryConnection:String?}
final class Network {
 var isReady=true,health=100,couplingAcknowledgements=true,couplingRevision:Int?=0,inventoryConnection:String?="one"
 var onInventoryConnection:((String?)->Void)?,onCouplings:(([NativeCouplingLink],Int,String)->Void)?
 var order:[String]=[],pending:[(Bool)->Void]=[],requestResult=true,onMove:(()->Void)?
 var sentPosition=SIMD3<Float>.zero,sentWork:Int?,sentKit:[Double]?,sentHealth=0,sentDamage="",sentHeading:Float=0,sentPitch:Float=0,sentRoll:Float=0
 var sentVelocity=SIMD3<Float>.zero,sentAngular=SIMD3<Float>.zero,sentPaused=true
 var exitWork:Int?,exitHealth=0,exitDamage="",exitFeet=SIMD3<Float>.zero,exitParked=SIMD3<Float>.zero
 // ACTUAL_POSITION_SIGNATURE
 {order.append("driver");sentPosition=position;sentWork=vehicleWork;sentKit=kit;sentHealth=vehicleHealth;sentDamage=vehicleDamage
  sentHeading=heading;sentPitch=pitch;sentRoll=roll;sentVelocity=velocity;sentAngular=angularVelocity;sentPaused=paused}
 // ACTUAL_EXIT_SIGNATURE
 {order.append("exit");exitWork=vehicleWork;exitHealth=vehicleHealth;exitDamage=vehicleDamage;exitFeet=feet;exitParked=position}
 func sendVehicleMove(_ id:String,state:[String:Any]){order.append("move:\(id)");onMove?()}
 func requestCoupling(parent:String,trailer:String?,kind:String,completion:@escaping(Bool)->Void)->Bool {
  guard requestResult else{return false};order.append("hitch");pending.append(completion);return true
 }
}
final class Renderer {
 var hasVehicleWorkingControls=false,hasJetNozzle=false,vehicleWorkingIsTow=false,canUnhitchVehicle=false
 var hasLandingGear=false,hasVehicleHorn=true,vehicleKind="car",supportsFootWeaponAim=true,canNativeFootMeleeGuard=false,isChuting=false
 var vehicleWorkingValue:Int?=2500,workingWrites=0
 var vehicleWorkingControl:Float=0 {didSet{workingWrites+=1}}
 var vehicleJetControl:Float=0
 var onCouplingRequest:((NativeVehicleCoupling.Request)->Bool)?
 var rejections:[NativeVehicleCoupling.Request]=[],connections:[String?]=[],applied:[Int]=[],released=0,crouches=0,exits=0
 var packets:[String:[String:Any]]=["middle":["x":1],"tail":["x":2]]
 var vehicleWirePosition=SIMD3<Float>(10,20,30),position=SIMD3<Float>(1,2,3)
 var direction:Float=0.2,drivingSpeed:Float=12,steeringInput:Float=0.3,vehicleNose:Float=0.4,vehicleRoll:Float=0.5
 var vehicleHealth=876,vehicleDamage="retained",vehicleLights=true,vehicleHorn=true,vehicleSiren=true
 var personalFlightPitch:Float=0,personalFlightRoll:Float=0,footWireAirborne=false,effectiveWireWeapon=0,isFiring=false,footWireAnimation:String?=nil,crouching=false
 var swimmingState=0,swimmingPitch:Float=0,swimmingRatio:Float=0,footWireMovementRatio:Double=0,footWireAim:Double?=nil
 var riderWireAction=1,footWireAction=0,currentWireVelocity=SIMD3<Float>(1,2,3),currentWireAngularVelocity=SIMD3<Float>(4,5,6)
 func vehicleWireKit(tuck:Double)->[Double]?{[tuck,2,3]}
 func vehicleCouplingMovePacket(_ id:String)->[String:Any]?{packets[id]}
 func rejectVehicleCoupling(_ request:NativeVehicleCoupling.Request){rejections.append(request)}
 func setVehicleCouplingConnection(_ value:String?){connections.append(value)}
 func applyVehicleCouplings(_ links:[NativeCouplingLink],revision:Int,connection:String){applied.append(revision)}
 func releaseVehicleCoupling(secondOnly:Bool=false){released+=1}
 func cancelWeaponInput(){};func cancelReloadAnimation(){}
 func toggleCrouch(){crouches+=1}
 func exitVehicle(){exits+=1;position=SIMD3(99,98,97);vehicleWorkingValue=nil;vehicleHealth=0;vehicleDamage=""}
}
final class Game {
 let network=Network(),gameplay=Gameplay(),weaponCycle=NativeWeaponCycleQueue(),radio=Radio(),gameHUD=HUD(),status=Status()
 let vehicleButton=Button(),radioButton=Button(),runButton=Button(),jumpButton=Button(),gasButton=Button(),brakeButton=Button()
 let weaponButton=Button(),reloadButton=Button(),aimButton=Button(),crouchButton=Button(),attackButton=Button()
 let weapons=NativeWeaponState(catalog:[
  .init(id:22,name:"Pistol",model:"",range:30,capacity:17,interval:0.3,animation:"",fireKind:"INSTANT_HIT"),
  .init(id:40,name:"Detonator",model:"",range:0,capacity:1,interval:0.3,animation:"",fireKind:"USE"),
  .init(id:43,name:"Camera",model:"",range:0,capacity:36,interval:0.3,animation:"",fireKind:"CAMERA"),
  .init(id:44,name:"Night vision",model:"",range:0,capacity:0,interval:0.3,animation:"",fireKind:"USE"),
  .init(id:46,name:"Parachute",model:"",range:0,capacity:0,interval:0.3,animation:"",fireKind:"MELEE")],allowLegacySnapshots:true)
 var currentVehicle:RemoteVehicle?=RemoteVehicle(row:["root","Fixture","525",0,0,1,0])!,renderer:Renderer?=Renderer(),acceptsHeldInput=true
 var nozzleUpPressed=false,nozzleDownPressed=false,auxiliaryMode:String?,vehicleTuck:Double=0.6
 var firePressed=false,gasPressed=false,brakePressed=false,handbrakePressed=false,hornPressed=false,bunnyHopPressed=false,flightBrakePressed=false
 var aiming=false,resets=0,gears=0,revision=0
 func styleControl(_ button:Button,icon:String?,fallback:String,accessibility:String){button.accessibilityLabel=accessibility}
 func resetControls(){resets+=1;cancelAuxForTest()}
 func cancelAuxForTest(){
  // ACTUAL_RESET_AUX
 }
 func setAiming(_ value:Bool){aiming=value}
 func updateWeaponHUD(){updateAuxiliaryControls()}
 func toggleGear(){gears+=1}
 func applyWorking(_ working:Float,acceptsInput:Bool){
  // ACTUAL_AXIS
 }
 func select(_ id:Int){revision+=1;_ = weapons.apply(["revision":revision,"selected":id,"weapons":id==0 ? []:[["id":id,"clip":3,"rest":10]]])}
 func install(){
  // ACTUAL_CALLBACKS
 }
 // ACTUAL_METHODS
}
var checks=0
func check(_ v:Bool,_ m:String){checks+=1;precondition(v,m)}
let request=NativeVehicleCoupling.Request(parent:"middle",trailer:"tail",kind:.trailer,generation:12345)
let g=Game();g.install()
check(g.renderer!.onCouplingRequest?(request)==true,"Actual callback did not queue")
check(g.network.order==["driver","move:middle","move:tail","hitch"],"Hitch was published before full current poses")
check(g.network.sentPosition==SIMD3(10,20,30) && g.network.sentWork==2500 && g.network.sentKit==[0.6,2,3],"Forced driver pose omitted current physical working/kit state")
check(g.network.sentHeading==0.2 && g.network.sentPitch==0.4 && g.network.sentRoll==0.5 && g.network.sentHealth==876 && g.network.sentDamage=="retained" && g.network.sentVelocity==SIMD3(1,2,3) && !g.network.sentPaused,"Forced publication lost full state")
g.network.pending.removeFirst()(false)
check(g.renderer!.rejections==[request] && g.renderer!.rejections[0].generation==12345,"Rejected callback reconstructed/lost request generation")
g.network.order=[];check(g.requestVehicleCoupling(.init(parent:"root",trailer:nil,kind:.trailer,generation:77)),"Root detach request failed")
check(g.network.order==["driver","hitch"],"Owned root was redundantly moved through remote vmove")
g.network.inventoryConnection="replacement";g.network.pending.removeFirst()(false)
check(g.renderer!.rejections==[request],"Old nonce rejected a replacement helper request")
for blocked in ["offline","input","dead","no-owner","no-capability","no-baseline","missing-pose"] {
 let x=Game();if blocked=="offline"{x.network.isReady=false};if blocked=="input"{x.acceptsHeldInput=false};if blocked=="dead"{x.network.health=0}
 if blocked=="no-owner"{x.currentVehicle=nil};if blocked=="no-capability"{x.network.couplingAcknowledgements=false};if blocked=="no-baseline"{x.network.couplingRevision=nil};if blocked=="missing-pose"{x.renderer!.packets=[:]}
 check(!x.requestVehicleCoupling(request) && x.network.order.isEmpty,"Guard leaked partial/hitch traffic: \(blocked)")
}
let reentrant=Game();reentrant.network.onMove={reentrant.network.inventoryConnection="new"}
check(!reentrant.requestVehicleCoupling(request) && reentrant.network.order==["driver","move:middle"],"Pose callback crossed namespace before hitch")
let covered=Game();covered.acceptsHeldInput=false
check(!covered.requestVehicleCoupling(request) && covered.network.order.isEmpty,"Covered input allowed a new acquisition")
let release=NativeVehicleCoupling.Request(parent:"middle",trailer:nil,kind:.trailer,generation:23456)
check(covered.requestVehicleCoupling(release) && covered.network.order==["driver","move:middle","hitch"],"Covered input blocked safety detach or skipped fresh poses")
check(covered.network.sentPaused && covered.network.sentWork==2500,"Safety detach falsely published active input or omitted working state")
covered.network.pending.removeFirst()(false)
check(covered.renderer!.rejections==[release],"Covered detach lost its captured generation on rejection")
let staleRelease=Game();staleRelease.acceptsHeldInput=false;staleRelease.network.onMove={staleRelease.network.inventoryConnection="new"}
check(!staleRelease.requestVehicleCoupling(release) && staleRelease.network.order==["driver","move:middle"],"Covered detach crossed a stale namespace")
let exit=Game();exit.completeVehicleExit()
check(exit.network.exitWork==2500 && exit.network.exitHealth==876 && exit.network.exitDamage=="retained","Exit read working/damage/health after renderer reset")
check(exit.network.exitParked==SIMD3(10,20,30) && exit.network.exitFeet==SIMD3(99,98,97),"Exit mixed driver origin and completed pedestrian feet")
check(exit.currentVehicle==nil && exit.renderer!.exits==1 && exit.radio.stops==1,"Exit ownership did not complete")

let ui=Game();ui.renderer!.hasVehicleWorkingControls=true;ui.updateAuxiliaryControls()
let writes=ui.renderer!.workingWrites;ui.nozzleUpPressed=true
for _ in 0..<20 {ui.updateAuxiliaryControls()}
check(ui.nozzleUpPressed && ui.resets==0 && ui.renderer!.workingWrites==writes && ui.renderer!.vehicleWorkingValue==2500,"Async UI refresh reset held input or physical working value")
check(!ui.weaponButton.isHidden && !ui.reloadButton.isHidden && ui.weaponButton.accessibilityLabel.contains("raise working"),"Real working capabilities not shown")
ui.renderer!.vehicleWorkingIsTow=true;ui.updateAuxiliaryControls()
check(!ui.nozzleUpPressed && ui.renderer!.vehicleWorkingValue==2500 && ui.weaponButton.accessibilityLabel.contains("tow bar"),"Working mode transition retained old hold or reset physical value")
ui.pressNozzleUp();ui.pressNozzleDown();ui.releaseNozzleUp()
check(!ui.nozzleUpPressed && ui.nozzleDownPressed,"Releasing one auxiliary touch canceled the other finger")
ui.applyWorking(1,acceptsInput:true);check(ui.renderer!.vehicleWorkingControl==1,"Working input not applied")
ui.cancelAuxForTest();check(!ui.nozzleDownPressed && ui.renderer!.vehicleWorkingControl==0 && ui.renderer!.vehicleWorkingValue==2500,"Input cancellation reset physical working state")
ui.applyWorking(1,acceptsInput:false);check(ui.renderer!.vehicleWorkingControl==0,"Overlay leaked working input")
ui.renderer!.canUnhitchVehicle=true;ui.updateAuxiliaryControls();ui.toggleCrouch()
check(!ui.crouchButton.isHidden && ui.crouchButton.accessibilityLabel=="Unhitch vehicle" && ui.renderer!.released==1 && ui.gears==0,"Coupling action became a landing gear toggle")
let callback=Game();callback.install();callback.network.onInventoryConnection?("one")
check(callback.renderer!.connections.count==1 && callback.gameplay.inventoryConnection=="one","Namespace callback did not reset coupling owner")
callback.network.onCouplings?([],4,"stale");check(callback.renderer!.applied.isEmpty,"Stale topology callback reached renderer")
callback.network.onCouplings?([],4,"one");check(callback.renderer!.applied==[4] && callback.resets==0,"Topology UI update reset game controls")

let utility=Game();utility.currentVehicle=nil;utility.renderer!.supportsFootWeaponAim=false
for id in [43,44,46] {utility.select(id);utility.renderer!.supportsFootWeaponAim=id==43;utility.updateAuxiliaryControls();check(utility.attackButton.isHidden && utility.aimButton.isHidden && utility.reloadButton.isHidden,"Unsupported utility shows dead gun controls\(id)")}
utility.select(40);utility.updateAuxiliaryControls();check(!utility.attackButton.isHidden && utility.attackButton.title=="DETONATE" && utility.reloadButton.isHidden,"Implemented detonator lost its distinct action")
utility.select(46);utility.renderer!.isChuting=true;utility.updateAuxiliaryControls();check(!utility.attackButton.isHidden && utility.attackButton.title=="DEPLOY","Parachute utility lost real deploy action")
utility.network.health=0;utility.updateAuxiliaryControls();check(!utility.attackButton.isHidden && utility.attackButton.title=="RESPAWN","Dead parachutist lost respawn action")
print("PASS actual coupling controls: \(checks) full-pose/ACK-generation/exit/UI/working-touch/namespace/utility checks")
