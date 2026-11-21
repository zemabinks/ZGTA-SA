// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

// Animation and ground key functions are extracted literally from the actual
// renderer by the driver. No substitute controller/cache policy is invented.
@main enum NPCLifetimeTests {
    static func main()throws {
        let hex="53445044010000000200000002000000000000000000000000000000000000000800100018005000a000f00000000000010000000200000000000000081000000100000003010000"
        let bytes=stride(from:0,to:hex.count,by:2).map{offset->UInt8 in let index=hex.index(hex.startIndex,offsetBy:offset);return UInt8(hex[index..<hex.index(index,offsetBy:2)],radix:16)!}
        let graph=try NativeAmbientPedestrianPaths(data:Data(bytes),expectedCRC:"410b5926")
        let owner=NativeAmbientPedestrians();owner.configure(level:1,paths:graph.crc32);_=owner.install(graph)
        let row=NativeAmbientPedestrianProtocol.Free(identity:.init(id:1,skin:14,flags:0,seed:119),feet:SIMD3(1,2,3),goal:SIMD2(10,2),speed:0,desiredSpeed:1)
        owner.receive(.free(atServerMilliseconds:100000,[row]),serverNow:100000,received:100)
        let before=owner.frames(at:100,near:.zero)[0]
        owner.receive(.gone([1]),serverNow:100001,received:100.001)
        owner.receive(.free(atServerMilliseconds:100002,[row]),serverNow:100002,received:100.002)
        let after=owner.frames(at:100.002,near:.zero)[0]
        #if CHECK_GROUND_CONTEXT
        var context=after
        context.waitingLinkKind=5
        context.admittedAt=91.25
        let grounded=projectGround(context,z:7.5)
        guard grounded.generation==context.generation,grounded.admittedAt==context.admittedAt,
              grounded.waitingLinkKind==context.waitingLinkKind,grounded.id==context.id,
              grounded.skin==context.skin,grounded.seed==context.seed,grounded.flags==context.flags,
              grounded.position==SIMD3(context.position.x,context.position.y,7.5),
              grounded.velocity==context.velocity,grounded.heading==context.heading else {
            fatalError("Actual ground projection dropped NPC lifetime/context or changed motion")
        }
        #endif
        guard animationKey(before,name:"bmori") != animationKey(after,name:"bmori"),groundKey(before) != groundKey(after)else {
            print("FAIL same-ID/skin/seed respawn reuses actual renderer animation/ground identity");exit(1)
        }
        guard before.targetID==after.targetID,after.targetID=="p1" else{fatalError("Wire/combat target changed")}
        print("PASS actual typed lifetime and renderer key composition; no rendered frame, server or retail acceptance")
    }
}
