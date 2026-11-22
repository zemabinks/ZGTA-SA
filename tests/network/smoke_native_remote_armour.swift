// SPDX-License-Identifier: AGPL-3.0-only
// ACTUAL_COMMON
// ACTUAL_PACKET_OWNER
// ACTUAL_RENDER_SNAPSHOT
// ACTUAL_FIXTURE_LIBRARY

private enum Failure:Error {case failed(String)}
private var checks=0
private func check(_ yes:Bool,_ why:String)throws {checks+=1;if !yes{throw Failure.failed(why)}}
private func row(_ armour:Any,driver:Bool=false)->[Any] {
    var r=[Any](repeating:NSNull(),count:44)
    r[0]="remote";r[1]="Authored Remote";r[2]=driver ? "420":"s7"
    r[3]=0;r[4]=0;r[5]=13;r[6]=0;r[13]=0;r[14]=0;r[15]=0;r[16]=1000
    r[18]=driver ? 1000:100;r[27]=0;r[29]=0;r[30]=armour;r[32]=0;r[41]="ped/idle_stance/l/1";r[43]=100
    return r
}
@main private enum Main {
    static func main(){do{try run()}catch{fputs("FAIL \(error)\n",stderr);exit(1)}}
    static func run()throws {
        let values:[(Any,Double)]=[(0.5,0.5),(0.001,0.001),(0,0),(-0.25,-0.25),(1,1),(100,100),(250,250),
            (Double.greatestFiniteMagnitude,Double.greatestFiniteMagnitude),(-Double.greatestFiniteMagnitude,-Double.greatestFiniteMagnitude),
            (true,0),(false,0),("0.5",0),(NSNull(),0),(Double.nan,0),(Double.infinity,0),(-Double.infinity,0)]
        for driver in [false,true] {
            for (value,expected)in values {
                let packet=PacketOwner();packet.receive([row(value,driver:driver)],at:1)
                let player=packet.orderedPlayers[0]
                try check(player.armour==expected,"Primitive armour admission lost precision or imposed a life cap")
                try check(player.life==100,"Armour decoding changed independent life")
                try check(snapshot(player).armour==expected,"Actual renderer snapshot lost admitted armour")
            }
            let missing=PacketOwner();missing.receive([Array(row(1,driver:driver).prefix(30))],at:1)
            try check(missing.orderedPlayers[0].armour==0,"Absent armour column did not use0")
        }
        let library=fixture()
        for hz in [30,60,120] {
            for (before,after,wanted)in [(0.5,0.25,true),(0.5,0.5,false),(0.25,0.5,false),(1.5,0.5,true),(0.25,0.0,true),(0.0,0.0,false)] {
                let packet=PacketOwner(),animator=NativeRemoteFootAnimation(library:library,style:.init(),weapons:[:],random:{0.5})
                packet.receive([row(before)],at:1);_=animator.update(delta:0,nowMilliseconds:1000,snapshot:snapshot(packet.orderedPlayers[0]))
                let delta=1/Double(hz);packet.receive([row(after)],at:1+delta)
                let frame=animator.update(delta:delta,nowMilliseconds:1000+delta*1000,snapshot:snapshot(packet.orderedPlayers[0]))
                let reaction=frame.blends.contains{$0.clip=="ped/shot_partial" && $0.weight>0}
                try check(reaction==wanted,"Row-to-animation fractional damage reaction at\(hz)Hz")
                try check(!animator.animator.stunned && !animator.animator.dead,"Remote reaction acquired local input stun/death")
            }
        }
        var referenceCases=0
        if CommandLine.arguments.count>1 {
            let doc=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as![String:Any]
            for item in doc["cases"]as![[String:Any]] {
                let kind=item["kind"]as!String
                let value:Any=kind=="nan" ? Double.nan:kind=="infinity" ? Double.infinity:kind=="negative-infinity" ? -Double.infinity:item["value"]!
                let packet=PacketOwner();packet.receive([row(value,driver:item["role"]as!String=="driver")],at:1)
                try check(packet.orderedPlayers[0].armour==(item["armour"]as!NSNumber).doubleValue,"Selected private armour scalar record")
                referenceCases+=1
            }
        }
        print("PASS \(checks) actual armour admission/snapshot/reaction checks; \(referenceCases) optional selected scalar records; authored CLP, no app/GPU/retail claim")
    }
}
