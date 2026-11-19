let client=NativeMultiplayerClient(server:ServerAddress(CommandLine.arguments[1])!)
var checks=0,readyCount=0,phase=0,finished=false,teleports=0,callbacks:[String]=[],topologies:[String]=[],uncertainCallbacks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
let cab=RemoteVehicle(row:["cab","Fixture","525",0,0,1,0,0,0,1000,""])!
func request(_ parent:String,_ trailer:String?,_ kind:String="trailer",_ completion:@escaping(Bool)->Void)->Bool {
 client.requestCoupling(parent:parent,trailer:trailer,kind:kind,completion:completion)
}
check(!request("cab","first"){_ in preconditionFailure("Offline callback")},"Offline request queued")
client.onTeleport={_,_ in teleports+=1}
client.onCouplings={links,revision,nonce in
 topologies.append("\(nonce):\(revision)")
 check(client.couplingRevision==revision && client.couplingLinks==links,"Topology callback ran before stored state")
 if nonce=="coupling-2" {
  if revision==0 {
   check(client.isReady && client.couplingAcknowledgements,"Delayed baseline disabled ordinary readiness")
   for (parent,trailer,kind) in [("",Optional("first"),"trailer"),("cab",Optional("cab"),"trailer"),("cab",Optional("first"),"bad"),("bad\u{0}id",Optional("first"),"tow")] {
    check(!request(parent,trailer,kind){_ in preconditionFailure("Invalid callback")},"Invalid request consumed sequence")
   }
   client.sendPosition(.zero,heading:0,moving:false,running:false,vehicle:cab,vehicleWork:-4)
   client.sendVehicleMove("first",state:["x":0,"y":0,"z":1,"h":0,"p":0,"r":0,"hp":1000,"d":"","w":2500])
   check(request("cab","first"){accepted in
    callbacks.append("one");check(accepted && client.couplingRevision==1 && client.couplingLinks.count==1,"Accepted callback preceded topology")
    check(request("cab",nil){accepted in
     callbacks.append("two");check(!accepted,"Rejected request reported success")
     check(request("first","second"){accepted in
      callbacks.append("three");check(accepted && client.couplingRevision==2 && client.couplingLinks.map(\.parent)==["cab","first"],"Reordered equal revision reset topology/ACK")
      check(client.couplingAcknowledgements && teleports==2,"Duplicate hello downgraded capability or teleported")
      check(request("first",nil){_ in uncertainCallbacks+=1},"Fourth request did not queue")
     },"Third request failed")
    },"Detach request failed")
   },"First request failed")
  }else if revision==3 {
   check(callbacks==["one","two","three"],"Callbacks duplicated or stale ACK unlocked another request")
   phase=2;client.requestInventoryResync() // onTopology ownership change suppresses this packet's pending ACK callback
  }
 }else if nonce=="coupling-3" && revision==0 {
  check(!client.isReady,"Coupling baseline prematurely marked world ready")
  check(!request("tow","car","tow"){_ in preconditionFailure("Pre-ready callback")},"Pre-ready topology enabled hitch")
 }
}
client.onConnectionState={state in
 guard state == .ready else{return};readyCount+=1
 if readyCount==1 {
  check(!client.couplingAcknowledgements && client.couplingRevision==nil,"Legacy server acquired coupling capability")
  check(!request("cab","first"){_ in preconditionFailure("Legacy callback")},"Legacy server received coupling request")
  phase=1;client.requestInventoryResync()
 }else if readyCount==2 {
  check(client.couplingAcknowledgements && client.couplingRevision==nil,"Coupling capability did not wait for valid baseline")
  check(!request("cab","first"){_ in preconditionFailure("No-baseline callback")},"General readiness bypassed coupling baseline")
  client.sendChat("BASELINE PLEASE");client.sendPosition(.zero,heading:0,moving:false,running:false)
 }else if readyCount==3 {
  check(phase==2 && uncertainCallbacks==0 && client.couplingRevision==0 && client.couplingLinks.isEmpty,"Fresh peer retained/replayed uncertain coupling")
  client.sendPosition(.zero,heading:0,moving:false,running:false,vehicleWork:2500)
  client.sendPosition(.zero,heading:0,moving:false,running:false,vehicle:cab,vehicleWork:Int.max)
  client.sendPosition(.zero,heading:0,moving:false,running:false,vehicle:cab)
  client.sendExit(.zero,parked:.zero,heading:0,pitch:0,roll:0,vehicle:cab,vehicleHealth:1000,vehicleWork:-5)
  check(client.vehicles["cab"]?.work==0,"Parked row lost clamped working part")
  client.sendExit(.zero,parked:.zero,heading:0,pitch:0,roll:0,vehicle:cab,vehicleHealth:1000)
  check(request("tow","car","tow"){accepted in
   callbacks.append("fresh");check(accepted && client.couplingRevision==1 && client.couplingLinks==[.init(parent:"tow",trailer:"car",kind:"tow")],"Fresh sequence did not acknowledge")
   check(uncertainCallbacks==0 && callbacks==["one","two","three","fresh"],"Uncertain callback completed/replayed")
   check(topologies==["coupling-2:0","coupling-2:1","coupling-2:2","coupling-2:3","coupling-3:0","coupling-3:1"],"Malformed/stale/equal-reordered topology generated callbacks")
   client.disconnect();check(!client.couplingAcknowledgements && client.couplingRevision==nil && client.couplingLinks.isEmpty,"Disconnect retained topology")
   check(!request("tow",nil,"tow"){_ in preconditionFailure("Stopped callback")},"Stopped transport retried hitch")
   finished=true
  },"New peer first sequence failed")
 }else{preconditionFailure("Unexpected ready generation")}
}
client.onStatus={text in
 if text=="INVALID TOPOLOGIES CHECK" {check(callbacks.isEmpty && client.couplingRevision==0 && client.couplingLinks.isEmpty,"Malformed topology/ACK was applied")}
 if text=="CONTRADICTORY CHECK" {check(callbacks==["one"] && client.couplingLinks==[.init(parent:"cab",trailer:"first",kind:"trailer")],"Contradictory equal revision replaced topology or completed ACK")}
 if text=="STALE REVISION CHECK" {check(callbacks==["one","two"] && client.couplingRevision==2 && client.couplingLinks.count==2,"Stale revision delivered an old ACK or rewound topology")}
 if text=="OLD NONCE CHECK" {check(client.couplingRevision==0 && callbacks==["one","two","three"],"Old peer state/ACK crossed nonce boundary")}
}
client.connect();let deadline=Date().addingTimeInterval(45)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.005))}
check(finished,"Coupling wire fixture did not complete")
print("PASS actual coupling client: \(checks) checks, callbacks\(callbacks), topologies\(topologies), teleports\(teleports)")
