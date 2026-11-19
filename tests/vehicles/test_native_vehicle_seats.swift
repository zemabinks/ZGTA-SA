// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

let server=ServerAddress(CommandLine.arguments[1])!,controlURL=URL(string:CommandLine.arguments[2])!
let configuration=URLSessionConfiguration.ephemeral,session=URLSession(configuration:configuration)
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
func pump(){RunLoop.main.run(until:Date().addingTimeInterval(0.015))}
func wait(_ message:String,_ body:()->Bool){let deadline=Date().addingTimeInterval(10);while !body() && Date()<deadline{pump()};check(body(),message)}
func request(_ url:URL,_ body:[String:Any]?=nil)->[String:Any]{
 var req=URLRequest(url:url);if let body{req.httpMethod="POST";req.setValue("application/json",forHTTPHeaderField:"Content-Type");req.httpBody=try! JSONSerialization.data(withJSONObject:body)}
 var value:(Data?,URLResponse?,Error?)?;session.dataTask(with:req){value=($0,$1,$2)}.resume();wait("Fixture HTTP response"){value != nil}
 check((value!.1 as? HTTPURLResponse)?.statusCode==200,"Fixture HTTP status \((value!.1 as? HTTPURLResponse)?.statusCode ?? -1) \(url.path) \(body?["action"] as? String ?? "GET")")
 return try! JSONSerialization.jsonObject(with:value!.0!) as! [String:Any]
}
func control(_ action:String,_ args:[String:Any]=[:])->[String:Any]{if action != "report"{print("Fixture control: \(action)")};var body=args;body["action"]=action;return request(controlURL,body)}
func row(_ snapshot:[String:Any],native:Bool)->[Any]? {
 let browser=String(snapshot["browserNumber"] as! Int)
 return (snapshot["serverRows"] as? [[Any]])?.first{r in (r[0] as? String==browser) != native}
}
func point(_ row:[Any])->SIMD3<Float>{SIMD3((row[3] as! NSNumber).floatValue,(row[4] as! NSNumber).floatValue,(row[5] as! NSNumber).floatValue)}
_ = request(server.path("api/auth/me"))
let client=NativeMultiplayerClient(server:server,session:session)
defer{client.disconnect();session.invalidateAndCancel()}
var entries=0,driverEntries=0,denied=0,removed=0
client.onPassengerEnter={id,seat,ok in check(id=="shared-cab"&&seat>0,"Wrong passenger ACK identity");if ok{entries+=1}else{denied+=1}}
client.onEnter={id,ok in check(id=="shared-cab"&&ok,"Driver request failed");driverEntries+=1}
client.onVehicleRemoved={id in if id=="shared-cab"{removed+=1}}
client.connect();wait("Actual NMP baseline"){client.isReady&&client.vehicles["shared-cab"] != nil}
client.sendPosition(SIMD3(100,100,20),heading:0,moving:false,running:false)
_ = control("browserDrive")
wait("Browser driver row/marker"){client.orderedPlayers.contains{$0.vehicleID=="shared-cab"} && client.vehicles["shared-cab"]?.driverID != nil}
let car=client.vehicles["shared-cab"]!
check(client.requestEnter(car,seat:1),"Native passenger request not sent")
client.cancelVehicleEntry()
for _ in 0..<20{pump()}
check(client.passengerSeat==nil&&client.pendingVehicleEntry==nil&&entries==0,"Cancelled passenger ACK granted late seat")
check(client.requestEnter(car,seat:1),"Native passenger retry not sent")
wait("Correlated passenger ACK"){client.passengerSeat?.vehicle==car.id&&client.passengerSeat?.index==1}
client.sendPassengerPosition(SIMD3(100,100,20),heading:0,action:3,velocity:.zero,paused:false)
wait("Passenger row34 on real backend"){
 let report=control("report");guard let native=row(report,native:true),let seat=native[34] as? [Any]else{return false}
 return seat[0] as? String==car.id && (seat[1] as? NSNumber)?.intValue==1 && (native[2] as? String)?.hasPrefix("s")==true
}
check(!client.requestEnter(car,seat:2),"Seated passenger acquired another authority")
_ = control("browserMove",["x":160,"y":125,"z":20,"heading":0.75])
client.sendPassengerPosition(SIMD3(-2000,-2000,200),heading:0,action:0,velocity:SIMD3(999,0,0),paused:false)
wait("Passenger followed accepted browser driver"){
 let report=control("report");guard let native=row(report,native:true),let body=report["vehicle"] as? [Any]else{return false}
 let last=(report["nativeMessages"] as? [[String:Any]])?.last{$0["t"] as? String=="me"}
 return (last?["x"] as? NSNumber)?.intValue == -2000 && simd_distance(point(native),SIMD3(160,125,20))<4 && simd_distance(point(body),SIMD3(160,125,20))<0.01
}
let report=control("report"),messages=report["nativeMessages"] as! [[String:Any]],last=messages.last{$0["t"] as? String=="me"}!
check(last["walking"] as? Bool==true&&last["driving"] as? Bool==false&&last["riding"] as? String==car.id&&last["seat"] as? Int==1,"Actual passenger sender changed browser role contract")
check(last["parked"]==nil&&last["car"]==nil&&last["vehicle"]==nil,"Passenger published a driver body/parked identity")
client.sendPassengerExit(SIMD3(161,125,20),heading:0.25)
check(client.passengerSeat==nil,"Exit retained local passenger authority")
wait("Passenger release foot row"){
 let r=control("report");return row(r,native:true).map{$0[34] is NSNull} ?? false
}
check(simd_distance(point(control("report")["vehicle"] as! [Any]),SIMD3(160,125,20))<0.01,"Passenger exit moved shared vehicle")
_ = control("browserExit")
wait("Parked car restored"){client.vehicles[car.id]?.driverID==nil}
check(client.requestEnter(client.vehicles[car.id]!),"Native driver request")
wait("Native driver ACK"){driverEntries==1}
client.sendPosition(SIMD3(160,125,20),heading:0.25,moving:false,running:false,vehicle:client.vehicles[car.id])
_ = control("browserPassenger",["seat":1])
wait("Actual browser passenger decoded natively"){
 client.orderedPlayers.contains{$0.ridingVehicleID==car.id&&$0.ridingSeat==1&&$0.vehicleID==nil&&$0.skin==2}
}
client.sendPosition(SIMD3(210,160,21),heading:1,moving:true,running:false,vehicle:client.vehicles[car.id],speed:12,velocity:SIMD3(5,3,0))
wait("Browser passenger follows native driver"){
 let r=control("report");return row(r,native:false).map{simd_distance(point($0),SIMD3(210,160,21))<4} ?? false
}
_ = control("browserFoot")
wait("Browser detached natively"){client.orderedPlayers.allSatisfy{$0.ridingVehicleID==nil}}
client.sendExit(SIMD3(211,160,21),parked:SIMD3(210,160,21),heading:1,pitch:0,roll:0,vehicle:client.vehicles[car.id]!,vehicleHealth:900)
wait("Native parked after driver exit"){client.vehicles[car.id]?.driverID==nil}
_ = control("browserDrive")
wait("Browser reacquired driver"){client.orderedPlayers.contains{$0.vehicleID==car.id}}
check(client.requestEnter(client.vehicles[car.id]!,seat:1),"Final passenger request")
wait("Final passenger grant"){client.passengerSeat != nil}
client.sendPassengerPosition(SIMD3(210,160,21),heading:0,action:0,velocity:.zero,paused:false)
client.requestInventoryResync()
wait("Reconnect resets passenger/request authority"){client.isReady&&client.passengerSeat==nil&&client.pendingVehicleEntry==nil&&client.vehicles[car.id] != nil}
client.sendPosition(SIMD3(210,160,21),heading:0,moving:false,running:false)
check(client.requestEnter(client.vehicles[car.id]!,seat:1),"Fresh peer passenger request")
wait("Fresh peer passenger grant"){client.passengerSeat != nil}
client.sendPassengerPosition(SIMD3(210,160,21),heading:0,action:0,velocity:.zero,paused:false)
_ = control("deleteVehicle")
wait("Explicit deletion clears seat"){removed==1&&client.passengerSeat==nil&&client.vehicles[car.id]==nil}
client.disconnect();check(client.pendingVehicleEntry==nil&&client.passengerSeat==nil,"Disconnect retained seat/request")
let final:[String:Any]=["status":"PASS","checks":checks,"passengerGrants":entries,"driverGrants":driverEntries,"explicitRemovals":removed,
 "scope":"Actual unmodified NMP URLSession client against copied real backend and separate browser-shape peer; no Renderer/device performance claim"]
print(String(data:try! JSONSerialization.data(withJSONObject:final,options:[.sortedKeys]),encoding:.utf8)!)
