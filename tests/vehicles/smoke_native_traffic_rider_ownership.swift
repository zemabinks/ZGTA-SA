// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
private var checks=0
private func check(_ value:Bool,_ message:String){precondition(value,message);checks+=1}
private func close(_ a:SIMD3<Double>,_ b:SIMD3<Double>,_ message:String){check(simd_distance(a,b)<1e-9,message)}
private func hex(_ value:String)->Data {
    let bytes=Array(value);return Data(stride(from:0,to:bytes.count,by:2).map{UInt8(String(bytes[$0...$0+1]),radix:16)!})
}
@main private enum Main {
    static func main()throws {
        let retained=NativeTrafficRiderRetention<String>()
        check(retained.detach(id:1,generation:9,owner:"actual binding"),"Initial driver not retained")
        retained.retainPassenger(id:1,generation:9,seat:1,owner:"held ready passenger")
        retained.retainPassenger(id:1,generation:9,seat:1,owner:"duplicate")
        retained.retainPassenger(id:1,generation:9,seat:0,owner:"driver is not passenger")
        check(retained.passengers.count==1,"Passenger ownership duplicated or accepted driver slot")
        check(!retained.detach(id:1,generation:9,owner:"duplicate"),"Duplicate driver")
        retained.synchronize(generations:[1:9])
        check(retained.isThrown(id:1,generation:9),"Visible-seat culling reset thrown state")
        retained.advance(delta:4)
        check(retained.detached.count==1 && retained.detached[0].age==4,"Four-second equality expired")
        check(retained.passengers.count==1,"Driver timer controlled passenger lifetime")
        retained.synchronize(generations:[:])
        check(retained.detached.count==1 && !retained.isThrown(id:1,generation:9),"Car removal disposed detached actor")
        check(retained.passengers.isEmpty,"Removed car retained passenger")
        retained.advance(delta:.nan);retained.advance(delta:-1)
        check(retained.detached[0].age==4,"Invalid display time changed age")
        retained.advance(delta:0.000001)
        check(retained.detached.isEmpty,"Strict timeout not applied")
        check(retained.detach(id:1,generation:10,owner:"new generation"),"Reused ID inherited driver lifetime")
        retained.retainPassenger(id:1,generation:10,seat:1,owner:"new passenger")
        retained.complete(retained.detached[0].serial)
        check(retained.detached.isEmpty && retained.isThrown(id:1,generation:10),"Handoff allowed driver respawn")
        check(retained.passengers.count==1,"Driver handoff disposed independent passenger")
        retained.synchronize(generations:[1:10],promoted:[1])
        check(retained.passengers.isEmpty && retained.isThrown(id:1,generation:10),"Registered promotion left stale compact passenger or reset tombstone")
        retained.retainPassenger(id:1,generation:10,seat:2,owner:"native admission boundary")
        retained.synchronize(generations:[1:10],admitted:[])
        check(retained.passengers.isEmpty && retained.isThrown(id:1,generation:10),"Native scene retirement retained passenger or reset driver tombstone")
        retained.retainPassenger(id:1,generation:10,seat:2,owner:"reset passenger")
        retained.reset()
        check(!retained.isThrown(id:1,generation:10) && retained.passengers.isEmpty,"Full reset retained tombstone/passenger")
        for fps in [30,60,120] {
            let value=NativeTrafficRiderRetention<Int>();_ = value.detach(id:2,generation:1,owner:1)
            for _ in 0..<(fps*3){value.advance(delta:1/Double(fps))}
            check(value.detached.count==1,"Three-second driver disappeared at \(fps)FPS")
            for _ in 0..<(fps*2){value.advance(delta:1/Double(fps))}
            check(value.detached.isEmpty,"Expired driver remained at \(fps)FPS")
        }
        typealias H=NativeTrafficRiderHandoff
        typealias S=NativeTrafficOccupants.Seat
        func seat(_ id:UInt16,_ index:Int)->S{.init(id:id,generation:1,model:400,index:index,skin:index,dead:false)}
        let order=NativeTrafficOccupants.followOrder([seat(5,0),seat(5,1),seat(5,2),seat(2,0),seat(2,1)])
        check(order.map(\.id)==[5,5,5,2,2] && order.map(\.index)==[1,2,0,1,0],"Driver detached before current passenger update or reordered vehicles")
        let a=H.Destination(id:1,generation:8),b=H.Destination(id:2,generation:9)
        let source=H.Source(serial:1,skin:0,feet:SIMD3(0,0,900))
        func candidate(_ destination:H.Destination,_ x:Double,_ age:Double,_ skin:Int=0)->H.Candidate {
            .init(destination:destination,skin:skin,position:SIMD3(x,0,-900),admittedAt:100-age)
        }
        check(H.match(sources:[source],candidates:[candidate(a,1,5)],now:100,assigned:[:])[1]==a,"Skin zero, age equality or horizontal metric lost")
        for c in [candidate(a,4,1),candidate(a,1,5.00001),candidate(a,1,-0.01),candidate(a,1,1,7)] {
            check(H.match(sources:[source],candidates:[c],now:100,assigned:[:]).isEmpty,"Ineligible NPC claimed")
        }
        let other=H.Source(serial:2,skin:0,feet:SIMD3(1.25,0,0))
        let paired=H.match(sources:[source,other],candidates:[candidate(a,1,1),candidate(b,-1.5,1)],now:100,assigned:[:])
        check(paired[1]==b && paired[2]==a,"Earlier driver stole nearer driver's NPC")
        check(H.match(sources:[source,other],candidates:[candidate(a,1,1)],now:100,assigned:[1:a]).count==1,"Assigned NPC claimed twice")
        check(H.match(sources:[source],candidates:[candidate(a,1,1)],now:.nan,assigned:[:]).isEmpty,"Invalid clock admitted handoff")

        // Authored graph golden, not original world data.
        let data=hex("53445044010000000200000002000000000000000000000000000000000000000800100018005000a000f00000000000010000000200000000000000081000000100000003010000")
        let graph=try NativeAmbientPedestrianPaths(data:data,expectedCRC:NativeAmbientPedestrianPaths.crc32(data))
        typealias P=NativeAmbientPedestrianProtocol
        let identity=P.Identity(id:7,skin:0,flags:1,seed:119)
        let row=P.Free(identity:identity,feet:SIMD3(0,0,3.125),goal:SIMD2(0,0),speed:0,desiredSpeed:0)
        func owner()->NativeAmbientPedestrians {
            let value=NativeAmbientPedestrians();_ = value.configure(level:1,paths:graph.crc32);_ = value.install(graph)
            value.receive(.free(atServerMilliseconds:100000,[row]),serverNow:100000,received:100)
            return value
        }
        let feet=SIMD3(3.0,-2,3.125)
        for fps in [30,60,120] {
            let value=owner(),first=value.frames(at:100,near:.zero)[0]
            check(first.admittedAt==100 && value.contains(id:7,generation:first.generation),"Missing local NPC age/generation")
            check(!value.acceptRider(id:7,generation:first.generation+1,feet:feet,heading:1.25,at:100),"Foreign NPC generation accepted")
            check(!value.acceptRider(id:8,generation:first.generation,feet:feet,heading:1.25,at:100),"Handoff invented NPC")
            check(value.acceptRider(id:7,generation:first.generation,feet:feet,heading:1.25,at:100),"Existing NPC rejected")
            for i in 0...(fps*2) {
                let seconds=Double(i)/Double(fps),frame=value.frames(at:100+seconds,near:.zero)[0]
                let factor=exp(-min(seconds,1.5)/0.6-max(0,seconds-1.5)/0.3)
                close(frame.position,SIMD3(3*factor,-2*factor,3.125),"Rate-dependent arrival correction at \(fps)FPS")
                check(abs(frame.heading-1.25)<1e-12,"Down NPC turned after receiving rider heading")
            }
            check(value.count==1,"Handoff changed authoritative NPC count")
        }
        let continuity=owner(),first=continuity.frames(at:100,near:.zero)[0]
        _=continuity.acceptRider(id:7,generation:first.generation,feet:feet,heading:1.25,at:100)
        let before=continuity.frames(at:100.5,near:.zero)[0]
        let shifted=P.Free(identity:identity,feet:SIMD3(-6,0,3.125),goal:SIMD2(-6,0),speed:0,desiredSpeed:0)
        continuity.receive(.free(atServerMilliseconds:100500,[shifted]),serverNow:100500,received:100.5)
        let after=continuity.frames(at:100.5,near:.zero)[0]
        close(before.position,after.position,"Wire refresh discarded arrival correction within twelve metres")
        check(after.admittedAt==100,"Ordinary wire refresh renewed five-second handoff eligibility")
        continuity.receive(.gone([7]),serverNow:100501,received:100.501)
        check(!continuity.contains(id:7,generation:first.generation),"Removed NPC retained handoff identity")
        print("PASS \(checks) real retention, existing-NPC matching and correction checks; authored inputs, no renderer or retail claim")
    }
}
