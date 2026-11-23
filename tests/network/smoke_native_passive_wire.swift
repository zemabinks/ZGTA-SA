// SPDX-License-Identifier: AGPL-3.0-only
setbuf(stdout,nil)
let session=URLSession(configuration:.ephemeral)
let address=ServerAddress(CommandLine.arguments[1])!
let target=CommandLine.arguments[2]
let client=NativeMultiplayerClient(server:address,session:session)
// This protocol-only owner records the actual authoritative placement, as
// the App's renderer does. The transport must reject a missing owner.
var observedPlacement:SIMD3<Float>?
client.onTeleport={point,heading in
    precondition([point.x,point.y,point.z].allSatisfy(\.isFinite) && heading?.isFinite != false)
    observedPlacement=point
}
var phase=0,finished=false,trace:[Bool]=[],callbacks=0
client.onConnectionState={state in print("PASSIVE_WIRE_CONNECTION \(state)")}
func change(_ mode:String){
    session.dataTask(with:address.path("fixture/protection/"+mode)){_,response,error in
        precondition(error==nil && (response as?HTTPURLResponse)?.statusCode==200,"Actual server passive action failed")
    }.resume()
}
client.onPlayers={players in
    callbacks+=1;if callbacks<=8{print("PASSIVE_WIRE_ROWS target=\(target) \(players.map{($0.id,$0.passive)})")}
    guard let actor=players.first(where:{$0.id==target})else{return}
    precondition(actor.code=="s7" && actor.position==SIMD3<Float>(10,20,30))
    precondition(actor.life==100 && actor.armour==0,"Protection changed actor vitals")
    if phase==0 {
        precondition(!actor.passive);trace.append(actor.passive);phase=1;change("on")
    }else if phase==1 && actor.passive {
        trace.append(actor.passive);phase=2;change("off")
    }else if phase==2 && !actor.passive {
        trace.append(actor.passive);phase=3;finished=true;client.disconnect()
    }
}
client.connect()
let deadline=Date().addingTimeInterval(30)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
precondition(finished && observedPlacement != nil && trace==[false,true,false],"Actual native passive transport did not complete")
print("PASS actual native HTTP/WS passive trace: \(trace); no renderer or retail claim")
