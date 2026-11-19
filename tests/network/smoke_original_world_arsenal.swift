import Foundation
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
let catalog=(fixture["catalog"]as! [[String:Any]]).map{r in NativeOriginalWorldArsenal.Definition(id:r["id"]as! Int,slot:r["slot"]as! Int,capacity:r["capacity"]as! Int,kind:r["kind"]as! String,wait:(r["wait"]as! NSNumber).doubleValue,reload:(r["reload"]as! NSNumber).doubleValue)}
let arsenal=NativeOriginalWorldArsenal(definitions:catalog,slotCount:fixture["slotCount"]as! Int)
var checks=0,accept=true
func check(_ condition:@autoclosure()->Bool,_ message:String){checks+=1;if !condition(){fatalError(message)}}
func close(_ a:Double,_ b:Double,_ name:String){check(abs(a-b)<1e-7,name+" \(a) != \(b)")}
let operations=fixture["operations"]as! [[String:Any]]
for(index,row)in operations.enumerated(){
 let op=row["operation"]as! [String:Any],now=(row["now"]as! NSNumber).doubleValue,kind=op["op"]as! String
 var actualSent:[[String:Any]]=[]
 switch kind{
 case"tick":arsenal.tick((op["dt"]as! NSNumber).doubleValue)
 case"give":_ = arsenal.give(op["id"]as! Int,amount:(op["amount"]as! NSNumber).doubleValue)
 case"next":arsenal.next(op["direction"]as! Int,allowed:(op["allowed"]as? [Int]).map{Set($0)})
 case"take":_ = arsenal.take(op["id"]as! Int)
 case"drop":arsenal.drop(op["id"]as! Int)
 case"holster":arsenal.holster()
 case"spend":arsenal.spend(after:(op["after"]as! NSNumber).doubleValue)
 case"reload":arsenal.reload(held:op["held"]as! Bool)
 case"clear":arsenal.clear()
 case"heard":check(arsenal.receive(op["rows"],back:op["back"]as! Bool,now:now),"valid guns rows")
 case"revived":arsenal.revived()
 case"update","flush":
  if let rows=arsenal.outgoingInventory(now:now,flush:kind=="flush"){
   actualSent.append(["rows":rows,"accepted":accept]);if accept{arsenal.inventorySent(rows,now:now)}
  }
 case"accept":accept=op["value"]as! Bool
 default:fatalError(kind)
 }
 let expected=row["state"]as! [String:Any],label="operation\(index)\(kind)"
 check(arsenal.selectedID==expected["weapon"]as! Int,label+"selected")
 check(arsenal.slot==expected["slot"]as! Int,label+"slot")
 check(arsenal.ready==expected["ready"]as! Bool,label+"ready")
 check(arsenal.poised==expected["poised"]as! Bool,label+"poised")
 check(arsenal.dry==expected["dry"]as! Bool,label+"dry")
 check(arsenal.loadable==expected["loadable"]as! Bool,label+"loadable")
 if let ammo=expected["ammo"]as? [String:Int]{check(arsenal.ammo?.clip==ammo["clip"]&&arsenal.ammo?.reserve==ammo["rest"],label+"ammo")}else{check(arsenal.ammo==nil,label+"no ammo")}
 let items=expected["items"]as! [[String:Any]];check(items.count==arsenal.items.count,label+"items")
 for(a,b)in zip(arsenal.items,items){check(a.id==b["id"]as! Int&&a.slot==b["slot"]as! Int&&a.clip==b["clip"]as! Int&&a.reserve==b["reserve"]as! Int,label+"item");close(a.until,(b["until"]as! NSNumber).doubleValue,label+"until");close(a.again,(b["again"]as! NSNumber).doubleValue,label+"again")}
 check(NSArray(array:actualSent).isEqual(to:expected["sent"]as! [Any]),label+"outgoing \(actualSent) expected\(expected["sent"]!)")
}
arsenal.disconnect();check(!arsenal.synchronized&&arsenal.items.isEmpty,"disconnect")
check(arsenal.outgoingInventory(now:1e8,flush:true)==nil,"unnegotiated inventory")
check(!arsenal.receive("invalid",back:false,now:0),"invalid inventory")
_ = arsenal.give(22,amount:Double.greatestFiniteMagnitude);check(arsenal.ammo?.clip==17,"bounded huge amount")
arsenal.next(Int.max);arsenal.next(Int.min);check(arsenal.items.count==1,"bounded direction")
print("PASS original browser arsenal: \(operations.count) actual archived operations; \(checks) checks")
