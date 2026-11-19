// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

// This carrier executes the actual animation class and a literal Renderer
// dispatch block. Buffer identity is authored NSObject storage; no Metal/UI.
enum TestFailure:Error {case failed(String)}
var checks=0
func check(_ value:Bool,_ message:String)throws {
    checks+=1;if !value{throw TestFailure.failed(message)}
}
func near(_ a:Double,_ b:Double,_ message:String,_ tolerance:Double=1e-11)throws {
    try check(a.isFinite && b.isFinite && abs(a-b)<=tolerance,message+" (actual \(a), expected \(b))")
}
func same(_ a:NativeRemoteBikeAnimation.Frame,_ b:NativeRemoteBikeAnimation.Frame,_ label:String)throws {
    try near(a.lean,b.lean,label+" lean");try near(a.tuck,b.tuck,label+" tuck")
    try check(a.pedal==b.pedal,label+" pedal")
    if let x=a.crank,let y=b.crank {try near(x,y,label+" crank")}
    else {try check(a.crank==nil && b.crank==nil,label+" optional crank")}
    try near(a.hop,b.hop,label+" hop")
}
typealias Bike=NativeRemoteBikeAnimation
func sample(_ serial:Double=1,_ time:Double=10,_ lean:Double=0.2,
            mode:Int?=nil,phase:Double=0,speed:Double=8,yaw:Double=0.2,health:Double=1000)->Bike.Sample {
    let kit:[Double]=mode.map{[lean,0.25,Double($0),phase,-0.4]} ?? [lean]
    return .init(serial:serial,time:time,speed:speed,yawRate:yaw,health:health,kit:kit)
}
final class AuthoredBuffer:NSObject {}
struct AuthoredMesh {let vertices:AuthoredBuffer}
struct AuthoredPlayer {
    var id:String,code:String,vehicleID:String?
    var x:Double=4,y:Double=5,z:Double=6
}
struct AuthoredDefinition {var bike:[String:Double]?}
final class RendererCarrier {
    var remoteBikeAnimations:[String:Bike]=[:]
    var actorMeshes:[String:AuthoredMesh]=[:]
    func update(player:AuthoredPlayer,name:String,model:String,now:Double,delta:Double,
                samples:(Bike.Sample,Bike.Sample?))->Bike.Frame {
        let source=AuthoredDefinition(bike:["maxLean":0.6])
        let riderTime=now,riderDelta=delta
        // ACTUAL_RENDERER_DISPATCH
        return frame
    }
}

func compatibility()throws {
    // Unchanged public nil-default API and explicit nil are identical. This
    // control also executes against the historical class without its bridge.
    let implicit=Bike(),explicit=Bike()
    for i in 0..<160 {
        let time=10+Double(i)/60,serial=Double(i/6),packetTime=10+serial/10
        let current=sample(serial,packetTime,sin(serial)*0.5,mode:i%37<30 ? i%3:nil,phase:0.07*serial)
        let old=sample(serial-1,packetTime-0.1,sin(serial-1)*0.5,mode:1,phase:0.07*(serial-1))
        let a=implicit.update(model:i<120 ? "authored-a":"authored-b",maxLean:0.6,now:time,delta:1/60,sample:current,previous:old)
        let b=explicit.update(model:i<120 ? "authored-a":"authored-b",maxLean:0.6,now:time,delta:1/60,sample:current,previous:old,owner:nil)
        try same(a,b,"nil default compatibility \(i)")
    }
    // Known first-sample and unchanged-owner lean values, independent of any
    // owner machinery or copied recurrence implementation.
    let bike=Bike(),first=sample(1,10,0.2)
    try near(bike.update(model:"authored",maxLean:nil,now:10,delta:0,sample:first,previous:nil).lean,0.2,"first sample snaps")
    let next=sample(2,10.1,0.8)
    let expected=0.2+0.6*(1-exp(-0.04/0.08))
    try near(bike.update(model:"authored",maxLean:nil,now:10.1,delta:0.04,sample:next,previous:first).lean,expected,"unchanged nil owner eases")
    // Packet age: lean prediction stops after150ms and ignores long or zero
    // packet intervals. Crank age has its separate500ms ceiling.
    let before=sample(1,10,0.2),current=sample(2,10.1,0.4)
    for (now,wanted) in [(10.0,0.4),(10.2,0.6),(11.1,0.7)] {
        try near(Bike().update(model:"authored",maxLean:nil,now:now,delta:0,sample:current,previous:before).lean,wanted,"packet age prediction \(now)")
    }
    try near(Bike().update(model:"authored",maxLean:nil,now:11,delta:0,sample:sample(2,10.5,0.4),previous:before).lean,0.4,"long packet interval disables prediction")
    try near(Bike().update(model:"authored",maxLean:nil,now:11,delta:0,sample:current,previous:current).lean,0.4,"zero packet interval disables prediction")
    var noKit=sample();noKit.kit=nil
    try near(Bike().update(model:"authored",maxLean:0.6,now:10,delta:0,sample:noKit,previous:nil).lean,asin(-8*0.2/20),"authored fallback yaw lean")
    noKit.health=0
    let dead=Bike().update(model:"authored",maxLean:0.6,now:10,delta:0,sample:noKit,previous:nil)
    try near(dead.lean,0,"dead fallback lean");try check(dead.crank==nil && dead.pedal==nil,"absent kit has no crank")
    let capped=Bike().update(model:"authored",maxLean:nil,now:12,delta:0,sample:sample(1,10,0,mode:2,phase:0.2),previous:nil)
    try near(capped.crank!,0.3,"crank age500ms clamp")
}

func ownerChanges()throws {
    let assetA=AuthoredBuffer(),assetB=AuthoredBuffer()
    let original=Bike.Owner(appearance:"509.red",vehicleID:"authored-one",asset:ObjectIdentifier(assetA))
    let variants:[(String,Bike.Owner)]=[
        ("appearance",.init(appearance:"509.blue",vehicleID:original.vehicleID,asset:original.asset)),
        ("vehicle",.init(appearance:original.appearance,vehicleID:"authored-two",asset:original.asset)),
        ("ID removed",.init(appearance:original.appearance,vehicleID:nil,asset:original.asset)),
        ("asset",.init(appearance:original.appearance,vehicleID:original.vehicleID,asset:ObjectIdentifier(assetB))),
        ("asset removed",.init(appearance:original.appearance,vehicleID:original.vehicleID,asset:nil))]
    for (label,newOwner) in variants {
        let bike=Bike()
        _=bike.update(model:"509",maxLean:nil,now:10,delta:0,sample:sample(1,10,-0.3),previous:nil,owner:original)
        let frame=bike.update(model:"509",maxLean:nil,now:10.1,delta:0.01,sample:sample(2,10.1,0.7),previous:nil,owner:newOwner)
        try near(frame.lean,0.7,"OWNER_CHANGE_SNAP \(label)")
        let follow=bike.update(model:"509",maxLean:nil,now:10.2,delta:0.025,sample:sample(3,10.2,-0.5),previous:nil,owner:newOwner)
        try near(follow.lean,0.7+(-1.2)*(1-exp(-0.025/0.04)),"new owner then ordinary easing \(label)")
    }
    // Reconstructing equal values is not an owner change.
    let bike=Bike();_=bike.update(model:"509",maxLean:nil,now:10,delta:0,sample:sample(1,10,0.1),previous:nil,owner:original)
    let equal=Bike.Owner(appearance:original.appearance,vehicleID:original.vehicleID,asset:ObjectIdentifier(assetA))
    let unchanged=bike.update(model:"509",maxLean:nil,now:10.1,delta:0.01,sample:sample(2,10.1,0.9),previous:nil,owner:equal)
    try near(unchanged.lean,0.1+0.8*(1-exp(-0.01/0.04)),"equal owner values retain easing")
    let modelChange=bike.update(model:"510",maxLean:nil,now:10.2,delta:0.001,sample:sample(3,10.2,-0.6),previous:nil,owner:equal)
    try near(modelChange.lean,-0.6,"numeric model change still snaps")
    let firstIDless=Bike.Owner(appearance:"509.red",vehicleID:nil,asset:nil)
    let nowRegistered=Bike.Owner(appearance:"509.red",vehicleID:"authored-one",asset:ObjectIdentifier(assetA))
    let optional=Bike();_=optional.update(model:"509",maxLean:nil,now:10,delta:0,sample:sample(1,10,0.1),previous:nil,owner:firstIDless)
    try near(optional.update(model:"509",maxLean:nil,now:10.1,delta:0,sample:sample(2,10.1,0.8),previous:nil,owner:nowRegistered).lean,0.8,"nil to admitted ID/asset snaps")

    // Owner replacement changes easing, not the retained serial/owed/crank
    // state. The same packet ages100ms; it must not be reprojected as a new
    // packet merely because its appearance/mesh owner changed.
    for (label,newOwner) in variants {
        let crank=Bike()
        _=crank.update(model:"509",maxLean:nil,now:10,delta:0,sample:sample(1,10,0,mode:1,phase:0.1),previous:nil,owner:original)
        let packet=sample(2,10.1,0,mode:1,phase:0.3)
        let waiting=crank.update(model:"509",maxLean:nil,now:10.1,delta:0,sample:packet,previous:nil,owner:original)
        try near(waiting.crank!,0.1,"owed correction is initially retained")
        let snapped=crank.update(model:"509",maxLean:nil,now:10.2,delta:0,sample:packet,previous:nil,owner:newOwner)
        try near(snapped.crank!,0.3,"OWNER_CHANGE_SNAP retained owed+serial \(label)")
        let carried=crank.update(model:"509",maxLean:nil,now:10.24,delta:0.04,sample:packet,previous:nil,owner:newOwner)
        try near(carried.crank!,0.344,"same serial does not regenerate paid debt \(label)")
        let next=sample(3,10.3,0,mode:1,phase:0.5)
        _=crank.update(model:"509",maxLean:nil,now:10.35,delta:0,sample:next,previous:nil,owner:newOwner)
        let changedBack=crank.update(model:"509",maxLean:nil,now:10.35,delta:0,sample:next,previous:nil,owner:original)
        try near(changedBack.crank!,0.555,"new serial applies one age-corrected debt \(label)")
        var absent=next;absent.kit=nil
        _=crank.update(model:"509",maxLean:nil,now:10.4,delta:0,sample:absent,previous:nil,owner:original)
        let resumed=crank.update(model:"509",maxLean:nil,now:10.5,delta:0,sample:sample(4,10.5,0,mode:2,phase:0.8),previous:nil,owner:original)
        try near(resumed.crank!,0.8,"missing pedal kit rebases next packet without stale debt \(label)")
    }
}

func rendererDispatch()throws {
    let renderer=RendererCarrier(),first=AuthoredBuffer(),second=AuthoredBuffer()
    renderer.actorMeshes["authored-bike"] = .init(vertices:first)
    var a=AuthoredPlayer(id:"a",code:"509.red",vehicleID:"authored-one")
    let b=AuthoredPlayer(id:"b",code:"509.blue",vehicleID:nil)
    try check(a.x==b.x && a.y==b.y && a.z==b.z,"authored owners are co-located")
    _=renderer.update(player:a,name:"authored-bike",model:"509",now:10,delta:0,samples:(sample(1,10,-0.2),nil))
    _=renderer.update(player:b,name:"authored-bike",model:"509",now:10,delta:0,samples:(sample(1,10,0.3),nil))
    try check(renderer.remoteBikeAnimations.count==2 && renderer.remoteBikeAnimations["a"] !== renderer.remoteBikeAnimations["b"],"literal cache isolates co-located players")
    a.code="509.green"
    try near(renderer.update(player:a,name:"authored-bike",model:"509",now:10.1,delta:0.01,samples:(sample(2,10.1,0.8),nil)).lean,0.8,"OWNER_CHANGE_SNAP literal appearance argument")
    let independent=renderer.update(player:b,name:"authored-bike",model:"509",now:10.1,delta:0.01,samples:(sample(2,10.1,-0.7),nil))
    try near(independent.lean,0.3-1*(1-exp(-0.01/0.04)),"other co-located owner kept easing")
    a.vehicleID="authored-two"
    try near(renderer.update(player:a,name:"authored-bike",model:"509",now:10.2,delta:0.001,samples:(sample(3,10.2,-0.4),nil)).lean,-0.4,"OWNER_CHANGE_SNAP literal registry argument")
    renderer.actorMeshes["authored-bike"] = .init(vertices:second)
    try near(renderer.update(player:a,name:"authored-bike",model:"509",now:10.3,delta:0.001,samples:(sample(4,10.3,0.6),nil)).lean,0.6,"OWNER_CHANGE_SNAP literal asset argument")
    renderer.actorMeshes.removeValue(forKey:"authored-bike")
    try near(renderer.update(player:a,name:"authored-bike",model:"509",now:10.4,delta:0.001,samples:(sample(5,10.4,-0.8),nil)).lean,-0.8,"OWNER_CHANGE_SNAP literal optional asset removal")
    try check(a.vehicleID=="authored-two" && b.vehicleID==nil,"literal adapter preserves authored and absent registry IDs")
    let fresh=RendererCarrier(),newPlayer=AuthoredPlayer(id:"new",code:"509.authored",vehicleID:"new-bike")
    let packet=sample(90,20.2,0,mode:1,phase:0.2)
    let admitted=fresh.update(player:newPlayer,name:"authored-bike",model:"509",now:20.2,delta:0.2,samples:(packet,nil))
    try near(admitted.crank!,0.2,"literal new bike cannot borrow prior display interval")
    let next=fresh.update(player:newPlayer,name:"authored-bike",model:"509",now:20.4,delta:0.2,samples:(packet,nil))
    try near(next.crank!,0.42,"literal existing bike receives full hitch time")
    let duplicate=fresh.update(player:newPlayer,name:"authored-bike",model:"509",now:20.4,delta:0.2,samples:(packet,nil))
    try near(duplicate.crank!,next.crank!,"literal duplicate bike draw cannot replay time")
    withExtendedLifetime((first,second)) {}
}

do {
    try compatibility()
    if CommandLine.arguments.dropFirst().first != "compatibility" {
        try ownerChanges();try rendererDispatch()
    }
    print("PASS \(checks) actual remote-bike owner/clock/dispatch checks; authored storage only")
}catch {
    print("FAIL \(checks) \(error)");exit(2)
}
