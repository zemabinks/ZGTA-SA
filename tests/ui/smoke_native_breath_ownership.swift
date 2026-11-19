// SPDX-License-Identifier: AGPL-3.0-only
// Actual swim, renderer nonce method, inventory callback and HUD methods are
// inserted by the runner. UIKit and unrelated owners below are boundary spies.
var checks=0
func check(_ value:Bool,_ message:String){checks += 1;if !value{print("FAIL \(message)");exit(2)}}
final class Boundary {var calls=0;func disconnected(){calls+=1};func cancelReload(){calls+=1};func setConnection(_ value:String?){calls+=1}}
final class Gameplay {var inventoryConnection:String?}
final class Network {var legacy:Int?;var usesOriginalWorldProtocol=false;var onInventoryConnection:((String?)->Void)?}
final class Renderer {
 let swimController=NativeSwimController()
 private var selfhostBreathConnection:String?
 var health=73,armour=22;var stamina=188.0,heading=1.37;var cancels=0;var coupling:String?
 func setVehicleCouplingConnection(_ nonce:String?){coupling=nonce}
 func cancelWeaponInput(){cancels+=1};func cancelReloadAnimation(){cancels+=1}
 // ACTUAL_BREATH_CONNECTION
}
final class VC {
 let network=Network(),weapons=Boundary(),weaponCycle=Boundary(),audio=Boundary(),gameplay=Gameplay()
 var renderer:Renderer?=Renderer()
 func install(){
  // ACTUAL_INVENTORY_CALLBACK
 }
}
final class Bar {var isHidden=false;var progress:Float=0;var accessibilityLabel:String?}
final class Radar {var snapshots=0;func updateWorld(state:[String:Any]){snapshots+=1}}
final class HUD {
 let breath=Bar(),radar=Radar()
 // ACTUAL_UPDATE_BREATH
 // ACTUAL_UPDATE_WORLD
}
func drain(_ renderer:Renderer,_ rate:Int){
 renderer.swimController.enter(velocity:.zero,rising:0,depth:4)
 for _ in 0..<(rate*2){renderer.swimController.steer(push:1,sprint:1,pitch:-0.2);_ = renderer.swimController.step(delta:1/Double(rate),depth:4)}
 check(renderer.swimController.breath<0.9,"fixture did not deplete actual swim oxygen")
}

final class HealthClient {
 var healthPrediction=NativeHealthPrediction(),transportGeneration:UInt64=1
 var health=100,armour=50,isReady=true,deliveredRespawnSequence=0
 var onVitals:((Int,Int)->Void)?,onRespawn:(()->Void)?
 // ACTUAL_ACKNOWLEDGED_VITALS
}
func verifyServerTrace(_ path:String){
 let data=try!Data(contentsOf:URL(fileURLWithPath:path)),object=try!JSONSerialization.jsonObject(with:data)as![String:Any]
 let rows=object["healthTrace"]as![[String:Any]],client=HealthClient()
 var published:[(Int,Int)]=[];client.onVitals={published.append(($0,$1))}
 let initial=rows.first(where:{$0["stage"]as?String=="begin"})!["packet"]as![String:Any],ack=initial["healthAck"]as![String:Any]
 client.healthPrediction.begin(connection:ack["connection"]as!String,health:initial["health"]as!Int,armour:initial["armour"]as!Int,revision:ack["revision"]as!Int,processed:ack["processed"]as!Int)
 check(client.healthPrediction.hurt(to:91)?.sequence==1,"actual local fall prediction not issued")
 var firstDrown:[String:Any]?
 for row in rows.dropFirst(){
  let stage=row["stage"]as!String,packet=row["packet"]as![String:Any]
  check(client.applyAcknowledgedVitals(packet),"actual emitted server ACK rejected: "+stage)
  switch stage{
  case "drown-before-fall":
   check(client.health==87 && client.armour==50,"server drowning erased or duplicated pending fall");firstDrown=packet
  case "fall-ack":
   check(client.health==87 && client.armour==50,"accepted fall reapplied predicted loss")
   check(client.healthPrediction.impact(20)?.sequence==2,"actual impact prediction not issued")
  case "drown-before-impact":check(client.health==82 && client.armour==30,"drowning consumed pending impact armour twice")
  case "impact-ack":check(client.health==82 && client.armour==30,"impact ACK reapplied armour damage")
  default:check(false,"unexpected actual trace stage")
  }
  check(published.last?.0==client.health && published.last?.1==client.armour,"accepted native vitals did not reach presentation callback")
 }
 check(!client.applyAcknowledgedVitals(firstDrown!),"older drowning revision rewound accepted health")
 check(client.health==82 && client.armour==30,"stale ACK changed local health")
}

let variants=CommandLine.arguments.dropFirst()
if let index=CommandLine.arguments.firstIndex(of:"--server-trace"){verifyServerTrace(CommandLine.arguments[index+1])}
for rate in [30,60,120]{
 let vc=VC();vc.install();let renderer=vc.renderer!,hud=HUD()
 drain(renderer,rate)
 if variants.contains("historical-hud"){
  hud.updateBreath(renderer.swimController.displayBreath);let before=hud.breath.progress
  hud.updateWorld(state:["breath":0])
  check(hud.breath.progress==before,"HTTP snapshot overwrote locally predicted breath")
  continue
 }
 let motion=(renderer.swimController.on,renderer.swimController.state.rawValue,renderer.swimController.ratio,renderer.swimController.pitch)
 vc.network.onInventoryConnection?("authored-peer-a")
 check(abs(renderer.swimController.breath-1)<1e-10,"fresh selfhost peer oxygen not reset")
 check(renderer.swimController.on==motion.0 && renderer.swimController.state.rawValue==motion.1 && renderer.swimController.ratio==motion.2 && renderer.swimController.pitch==motion.3,"peer reset changed swim task")
 check(renderer.health==73 && renderer.armour==22 && renderer.stamina==188 && renderer.heading==1.37,"breath reset changed other local ownership")
 check(renderer.coupling=="authored-peer-a" && vc.gameplay.inventoryConnection=="authored-peer-a","existing connection propagation changed")
 drain(renderer,rate);let depleted=renderer.swimController.breath
 vc.network.onInventoryConnection?("authored-peer-a")
 check(renderer.swimController.breath==depleted,"same peer snapshot granted oxygen")
 vc.network.onInventoryConnection?(nil)
 check(renderer.swimController.breath==depleted,"disconnect granted oxygen")
 vc.network.onInventoryConnection?("authored-peer-b")
 check(renderer.swimController.breath==1,"new selfhost peer did not match fresh server oxygen")
 drain(renderer,rate)
 for stale in [-50,0,17,100,1000]{
  hud.updateBreath(renderer.swimController.displayBreath)
  let prior=(hud.breath.progress,hud.breath.isHidden,hud.breath.accessibilityLabel)
  hud.updateWorld(state:["breath":stale])
  check(hud.breath.progress==prior.0 && hud.breath.isHidden==prior.1 && hud.breath.accessibilityLabel==prior.2,"HTTP snapshot overwrote locally predicted breath")
 }
 check(hud.radar.snapshots==5,"breath fix dropped world/radar updates")
 renderer.swimController.stop();renderer.swimController.ashore(0.5)
 hud.updateBreath(renderer.swimController.displayBreath)
 check(!hud.breath.isHidden,"surfaced recovery hid depleted breath")
 renderer.swimController.ashore(20);hud.updateBreath(renderer.swimController.displayBreath)
 check(hud.breath.isHidden && hud.breath.progress==1,"full local recovery did not retire bar")
 for legacy in [false,true]{
  let other=VC();other.network.legacy=legacy ? 1:nil;other.network.usesOriginalWorldProtocol = !legacy;other.install()
  let actor=other.renderer!;drain(actor,rate);let old=actor.swimController.breath
  other.network.onInventoryConnection?("unrelated-profile")
  check(actor.swimController.breath==old,"selfhost breath reset leaked into external adapter")
  check(actor.coupling=="unrelated-profile" && other.gameplay.inventoryConnection=="unrelated-profile","external adapter lost existing inventory path")
 }
}
print("PASS breath ownership: \(checks) actual-method checks; authored owner boundaries; no rendered, server-clock, hardware or retail acceptance")
