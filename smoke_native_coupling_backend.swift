let address=ServerAddress(CommandLine.arguments[1])!
let session=URLSession(configuration:.ephemeral)
let client=NativeMultiplayerClient(server:address,session:session)
var checks=0,readyCount=0,phase=0,finished=false,guestEstablished=false,uncertainCallbacks=0
var root:RemoteVehicle!,firstNonce:String?,callbacks:[Bool]=[],baselineNonces:[String]=[]
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
func publishDriver(_ work:Int=1234){client.sendPosition(SIMD3<Float>(100,100,20),heading:0,moving:false,running:false,vehicle:root,vehicleWork:work)}
func move(_ id:String,_ y:Double){client.sendVehicleMove(id,state:["x":100,"y":y,"z":20,"h":0,"p":0,"r":0,"hp":1000,"d":"","w":432])}
func request(_ parent:String,_ target:String?,_ completion:@escaping(Bool)->Void){check(client.requestCoupling(parent:parent,trailer:target,kind:"trailer",completion:completion),"Ready valid request did not enqueue")}
check(!client.requestCoupling(parent:"unavailable",trailer:nil,kind:"trailer"){_ in preconditionFailure("Offline callback")},"Offline request queued")
client.onCouplings={links,revision,connection in
 check(client.couplingRevision==revision && client.couplingLinks==links,"Callback before stored topology")
 if !client.isReady {
  baselineNonces.append(connection)
  check(links.isEmpty,"Fresh peer retained claims")
  check(!client.requestCoupling(parent:"unavailable",trailer:nil,kind:"trailer"){_ in preconditionFailure("Pre-ready callback")},"Baseline prematurely enabled requests")
 }
}
client.onConnectionState={state in
 guard state == .ready else{return};readyCount+=1
 check(guestEstablished && client.couplingAcknowledgements && client.couplingRevision != nil,"Ready missing actual HTTP guest/negotiation/baseline")
 check(client.couplingLinks.isEmpty,"Ready retained topology")
 root=client.orderedVehicles.first{$0.code.hasPrefix("8001.")}
 check(root != nil,"Synthetic owned tractor absent from actual fullState")
 if readyCount==1 {
  firstNonce=client.inventoryConnection;phase=1
  publishDriver();move("a",95);move("b",90);move("c",85)
  request(root.id,"a"){accepted in
   callbacks.append(accepted);check(accepted && client.couplingLinks.count==1,"Authority rejected aligned first link")
   request("a","b"){accepted in
    callbacks.append(accepted);check(accepted && client.couplingLinks.count==2,"Authority rejected aligned second link")
    request("b","c"){accepted in
     callbacks.append(accepted);check(!accepted && client.couplingLinks.count==2,"Authority accepted third link or rewound topology")
     request("a",nil){accepted in
      callbacks.append(accepted);check(accepted && client.couplingLinks==[.init(parent:root.id,trailer:"a",kind:"trailer")],"Sequence after rejected third did not release only second")
      request(root.id,nil){accepted in
       callbacks.append(accepted);check(accepted && client.couplingLinks.isEmpty,"Root release did not clear authoritative topology")
       phase=2
       client.sendExit(SIMD3<Float>(101,100,20),parked:SIMD3<Float>(100,100,20),heading:0,pitch:0,roll:0,vehicle:root,vehicleHealth:1000,vehicleWork:1876)
       check(client.vehicles[root.id]?.work==1876,"Native parked row lost work")
      }
     }
    }
   }
  }
 }else if readyCount==2 {
  check(phase==3 && uncertainCallbacks==0,"Uncertain ACK callback escaped disconnect")
  check(client.inventoryConnection != firstNonce && baselineNonces.count==2,"Reconnect did not establish fresh nonce/baseline")
  check(root.work==1876,"Real fullState lost saved parked work")
  publishDriver(2500);move("a",95)
  request(root.id,"a"){accepted in
   callbacks.append(accepted);check(accepted && uncertainCallbacks==0 && client.couplingLinks.count==1,"Fresh sequence one failed or old pending replayed")
   phase=4
   client.sendExit(SIMD3<Float>(101,100,20),parked:SIMD3<Float>(100,100,20),heading:0,pitch:0,roll:0,vehicle:root,vehicleHealth:1000,vehicleWork:2000)
  }
 }else{preconditionFailure("Unexpected third peer")}
}
client.onStatus={text in
 if text=="FIXTURE PARKING SEEN" {
  check(phase==2,"Parking marker out of order")
  // Real authoritative trailer cooldown; do not change Date.now or source constants.
  DispatchQueue.main.asyncAfter(deadline:.now()+2.6){
   check(client.isReady,"Transport lost during cooldown");phase=3;publishDriver(1876);move("a",95);move("b",90)
   request(root.id,"a"){accepted in
    callbacks.append(accepted);check(accepted,"Reacquire after real cooldown failed")
    request("a","b"){_ in uncertainCallbacks+=1}
   }
  }
 }else if text=="FIXTURE COMPLETE" {
  check(phase==4 && callbacks==[true,true,false,true,true,true,true],"Callbacks lost, duplicated or replayed")
  check(uncertainCallbacks==0 && client.couplingLinks.isEmpty,"Final parking did not release authoritative claim")
  client.disconnect();check(!client.isReady && client.couplingRevision==nil,"Explicit stop retained ready topology")
  check(!client.requestCoupling(parent:root.id,trailer:nil,kind:"trailer"){_ in preconditionFailure("Stopped callback")},"Stopped request queued")
  finished=true
 }
}
// This HTTP request establishes an actual guest cookie in the same private
// URLSession used for the WebSocket, rather than injecting a player identifier.
session.dataTask(with:address.path("api/local/state")){data,response,error in
 precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200 && data != nil)
 DispatchQueue.main.async{guestEstablished=true;client.connect()}
}.resume()
let deadline=Date().addingTimeInterval(55)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.005))}
check(finished,"Actual backend coupling fixture did not complete")
print("PASS native coupling backend: \(checks) checks, 2 ready namespaces, 7 delivered ACK callbacks, accepted uncertain ACK suppressed")
