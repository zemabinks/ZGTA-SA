import Foundation
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
let raw=fixture["catalog"]as! [[String:Any]]
let definitions=raw.map{r in NativeOriginalWorldArsenal.Definition(id:r["id"]as! Int,slot:r["slot"]as! Int,capacity:r["capacity"]as! Int,kind:r["kind"]as! String,wait:(r["wait"]as! NSNumber).doubleValue,reload:(r["reload"]as! NSNumber).doubleValue)}
let catalog=definitions.map{d in NativeWeaponState.Weapon(id:d.id,name:"QA\(d.id)",model:"",range:40,capacity:d.capacity,interval:0.1,animation:"fixture",fireKind:d.kind)}
let document:[String:Any]=["schema":1,"protocol":38,"definitions":raw]
let baseline=fixture["baseline"]as! [[Int]]
var checks=0
func check(_ condition:@autoclosure()->Bool,_ message:String){checks+=1;if !condition(){fatalError(message)}}
func make(_ ready:Bool=true)->NativeWeaponState {
 let target=NativeWeaponState(catalog:catalog,policy:.originalWorld,originalDefinitions:ready ? definitions:[],clock:{0})
 check(target.applyOriginalGuns(baseline),"source initial carried state");return target
}
func run(_ op:[String:Any],_ target:NativeWeaponState){switch op["type"]as! String {
 case "staff":check(target.applyOriginalStaffWeapons(op["packet"]as! [String:Any],alive:op["alive"]as? Bool ?? true),"valid original staff envelope")
 case "guns":check(target.applyOriginalGuns(op["rows"],back:op["back"]as! Bool),"valid original carried update")
 case "revive":target.reviveOriginalWeapons()
 default:fatalError("operation")
}}
func compare(_ target:NativeWeaponState,_ expected:[String:Any],_ label:String){
 check(target.selected==expected["selected"]as! Int,label+" selection")
 check(target.rounds==expected["rounds"]as! Int&&target.reserve==expected["reserve"]as! Int,label+" ammo")
 check(target.weapons.map(\.id).filter{$0 != 0}.sorted()==expected["ids"]as! [Int],label+" ownership")
 var wire:[[[Int]]]=[];if let rows=target.outgoingOriginalGuns(flush:true){wire.append(rows);target.originalGunsSent(rows)}
 check(NSArray(array:wire).isEqual(to:expected["wire"]as! [Any]),label+" wire \(wire) != \(expected["wire"]!)")
}
let target=make()
let operations=fixture["operations"]as! [[String:Any]]
for (index,row)in operations.enumerated(){run(row["operation"]as! [String:Any],target);compare(target,row["state"]as! [String:Any],"staff\(index)")}
for(index,batch)in (fixture["batches"]as! [[String:Any]]).enumerated(){
 let delayed=make(false)
 for op in batch["operations"]as! [[String:Any]]{run(op,delayed)}
 check(!delayed.synchronized && !delayed.canFire,"deferred metadata cannot unlock inventory")
 check(delayed.installClientWeaponCatalog(document),"actual async sidecar install")
 compare(delayed,batch["state"]as! [String:Any],"FIFO\(index)")
}
for policy in [NativeWeaponState.Policy.acknowledgedSelfHost,.legacySAMP]{
 let other=NativeWeaponState(catalog:catalog,policy:policy,originalDefinitions:definitions,clock:{0})
 check(!other.applyOriginalStaffWeapons(["give":[39,5],"arm":[[22,10]],"disarm":true]),"staff cannot cross protocol owner")
 check(other.weapons.map(\.id)==[0] && !other.synchronized,"staff cannot unlock another owner")
}
let direct=make();check(direct.giveClientWeapon(39,amount:2)&&direct.weapons.contains{$0.id==40},"source c6.give pairs detonator")
check(direct.removeClientWeapon(39) && !direct.weapons.contains{$0.id==39||$0.id==40},"source c6.putDown removes paired detonator")
check(!direct.applyOriginalStaffWeapons(["t":"other","give":[22,10]]),"wrong envelope rejected")
print("PASS actual original staff arsenal: \(operations.count) observed operations and 36 deferred-metadata batches; \(checks) checks")
