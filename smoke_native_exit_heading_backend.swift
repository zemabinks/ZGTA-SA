let address=ServerAddress(CommandLine.arguments[1])!,session=URLSession(configuration:.ephemeral)
let client=NativeMultiplayerClient(server:address,session:session)
let cases:[(Float,Float?)]=[(0.7,1.9),(-3.13,3.13),(3.13,-3.13),(0,.pi/2),(2.8,-2.4),(0.4,nil),(-0.8,.nan),(1.1,.infinity),(-1.1,-.infinity)]
var started=false,finished=false,index=0,checks=0
func check(_ value:Bool,_ text:String){checks+=1;precondition(value,text)}
func drive(_ i:Int){
 index=i;let item=cases[i]
 guard let car=client.vehicles["fixture-heading"] else{preconditionFailure("Fixture car missing")}
 client.sendPosition(SIMD3(1570,-2460,13.6),heading:item.0,moving:false,running:false,vehicle:car,vehicleHealth:1000)
}
client.onConnectionState={state in if state == .ready && !started {started=true;drive(0)}}
client.onStatus={text in
 if text=="EXIT HEADING \(index)" {
  let item=cases[index]
  client.sendExit(SIMD3(1572,-2460,13.6),parked:SIMD3(1570,-2460,13.6),heading:item.0,pitch:0.15,roll:-0.2,
    vehicle:client.vehicles["fixture-heading"]!,vehicleHealth:1000,footHeading:item.1)
  check(client.vehicles["fixture-heading"]!.heading==item.0,"Actor facing overwrote local parked body")
  check(client.health==100 && client.armour==25,"Exit orientation changed vitals")
 }else if text=="NEXT HEADING \(index+1)" {drive(index+1)}
 else if text=="EXIT HEADINGS COMPLETE" {check(index==cases.count-1,"Missing heading cases");finished=true;client.disconnect()}
}
session.dataTask(with:address.path("api/local/state")){data,response,error in
 precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200 && data != nil)
 DispatchQueue.main.async{client.connect()}
}.resume()
let deadline=Date(timeIntervalSinceNow:25)
while !finished && Date()<deadline {RunLoop.main.run(until:Date(timeIntervalSinceNow:0.005))}
check(finished,"Native exit-heading transport timed out")
print("PASS actual native exit heading client: \(checks) checks; separate first-foot/body yaw, wrap boundaries and safe optional fallback")
