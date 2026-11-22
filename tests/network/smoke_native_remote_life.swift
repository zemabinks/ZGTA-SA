// SPDX-License-Identifier: AGPL-3.0-only
// ACTUAL_COMMON
// ACTUAL_PACKET_OWNER

private struct Failure:Error,CustomStringConvertible {let description:String}
@main private enum Main {
    static func main(){do{try run()}catch{fputs("FAIL \(error)\n",stderr);exit(42)}}
    static func run()throws {
        var checks=0,referenceCases=0
        func check(_ value:Bool,_ text:String)throws{checks+=1;if !value{throw Failure(description:text)}}
        func row(_ value:Any,driver:Bool)->[Any]{
            var r=[Any](repeating:NSNull(),count:44)
            r[0]="actor";r[1]="Authored Actor";r[2]=driver ? "420":"s7"
            r[3]=0;r[4]=0;r[5]=13;r[6]=0;r[13]=0;r[14]=0;r[15]=0;r[16]=1000
            r[18]=driver ? 1000:value;r[27]=0;r[29]=0;r[32]=64
            r[41]="ped/walk_player/l/1";r[43]=driver ? value:100
            return r
        }
        func receive(_ value:Any,driver:Bool)->RemotePlayer{let owner=PacketOwner();owner.receive([row(value,driver:driver)],at:1);return owner.orderedPlayers[0]}
        let cases:[(String,Any,Double)]=[
            ("fraction",0.5,0.5),("tiny",0.001,0.001),("zero",0,0),("negative",-0.25,-0.25),
            ("one",1,1),("maximum",100,100),("above",250,100),("true",true,100),("false",false,100),
            ("string","0.5",100),("null",NSNull(),100),("nan",Double.nan,100),("infinity",Double.infinity,100),
            ("negative-infinity",-Double.infinity,100),("largest",Double.greatestFiniteMagnitude,100),
            ("lowest",-Double.greatestFiniteMagnitude,-Double.greatestFiniteMagnitude)]
        for driver in [false,true] {
            for(kind,value,expected)in cases {
                let player=receive(value,driver:driver)
                try check(player.life==expected,"\(driver) \(kind) canonical life was truncated/coerced/unbounded")
                try check(player.animation == (!driver && expected<=0 ? "death_front":"walk_player"),"\(kind) animation alive state differs from canonical life")
                try check(player.burning,"Numeric admission must preserve actor effect bits")
                try check(player.vehicleHealth==1000,"Driver life admission must not replace vehicle health")
            }
            let owner=PacketOwner();owner.receive([Array(row(0.5,driver:driver).prefix(6))],at:1)
            try check(owner.orderedPlayers[0].life==100,"Missing life defaults to100")
        }
        if CommandLine.arguments.count>1 {
            let reference=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
            for item in reference["cases"]as! [[String:Any]] {
                let kind=item["kind"]as! String,driver=(item["role"]as! String)=="driver"
                guard let c=cases.first(where:{$0.0==kind})else{throw Failure(description:"Unknown reference case")}
                let p=receive(c.1,driver:driver),expected=(item["life"]as! NSNumber).doubleValue
                try check(p.life==expected && (p.life>0)==(item["alive"]as! Bool),"Selected source \(kind)/\(driver) life/alive mismatch");referenceCases+=1
            }
        }
        print("PASS remote life \(checks) checks, \(referenceCases) optional selected source records")
    }
}
