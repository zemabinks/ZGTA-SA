// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Independent codecs for the published open.mp legacy203/206 layouts.
/// Reference: openmultiplayer/open.mp@2b4a69dd606dc2f93e98b0f1ffe8801cc01633f5,
/// Shared/NetCode/core.hpp. Camera and shot points remain physical GTA space;
/// pedestrian root/feet conversion is not applied here. A bullet has no damage
/// amount, body part or health acknowledgement.
enum NativeSAMPCombatSync {
    enum Failure:Error {case invalid,truncated}
    struct Aim:Equatable {
        var cameraMode:UInt8
        var front,position:SIMD3<Float>
        var aimZ:Float
        var zoom:UInt8,weaponState:UInt8,aspectRatio:UInt8
        var cameraFOV:Float{Float(zoom)/63*35+35}
        var aspect:Float{Float(aspectRatio)/255+1}
    }
    enum HitType:UInt8 {case none=0,player=1,vehicle=2,object=3,playerObject=4}
    struct Bullet:Equatable {
        var hitType:HitType
        var hitID:UInt16
        var origin,position,offset:SIMD3<Float>
        var weapon:UInt8
    }
    struct Remote<Value:Equatable>:Equatable {let player:UInt16,value:Value}
    private static func finite(_ value:SIMD3<Float>)->Bool{value.x.isFinite && value.y.isFinite && value.z.isFinite}
    private static func lengthSquared(_ value:SIMD3<Float>)->Double{Double(value.x)*Double(value.x)+Double(value.y)*Double(value.y)+Double(value.z)*Double(value.z)}
    private static func validate(_ value:Aim)throws {
        guard finite(value.front),finite(value.position),value.aimZ.isFinite,value.zoom<=63,value.weaponState<=3,
              lengthSquared(value.front)>0,lengthSquared(value.front)<1.5 else{throw Failure.invalid}
    }
    private static func validate(_ value:Bullet)throws {
        guard finite(value.origin),finite(value.position),finite(value.offset),value.weapon<=46,
              lengthSquared(value.origin)<=400_000_000,
              lengthSquared(value.offset)<=(value.hitType == .none ? 400_000_000:1_000_000),
              value.hitType == .none || value.hitID != .max else{throw Failure.invalid}
    }
    static func aim(_ value:Aim,sender:UInt16?=nil)throws->Data {
        try validate(value);if sender == .max{throw Failure.invalid}
        var w=NativeSAMPProtocol.Writer();w.integer(203,size:1)
        if let sender{w.integer(UInt32(sender),size:2)}
        w.integer(UInt32(value.cameraMode),size:1);w.vector(value.front);w.vector(value.position);w.float(value.aimZ)
        w.integer(UInt32(value.zoom | (value.weaponState<<6)),size:1);w.integer(UInt32(value.aspectRatio),size:1)
        return w.data
    }
    static func bullet(_ value:Bullet,sender:UInt16?=nil)throws->Data {
        try validate(value);if sender == .max{throw Failure.invalid}
        var w=NativeSAMPProtocol.Writer();w.integer(206,size:1)
        if let sender{w.integer(UInt32(sender),size:2)}
        w.integer(UInt32(value.hitType.rawValue),size:1);w.integer(UInt32(value.hitID),size:2)
        w.vector(value.origin);w.vector(value.position);w.vector(value.offset);w.integer(UInt32(value.weapon),size:1)
        return w.data
    }
    private static func reader(_ data:Data,tag:UInt32,remote:Bool,bytes:Int)throws->(NativeSAMPProtocol.Reader,UInt16?) {
        guard data.count==bytes+(remote ? 2:0)else{throw data.count<bytes+(remote ? 2:0) ? Failure.truncated:Failure.invalid}
        var r=try NativeSAMPProtocol.Reader(data);guard try r.integer(1)==tag else{throw Failure.invalid}
        let sender=remote ? UInt16(try r.integer(2)):nil
        guard sender != .max else{throw Failure.invalid};return(r,sender)
    }
    private static func readAim(_ data:Data,remote:Bool)throws->(Aim,UInt16?) {
        var (r,sender)=try reader(data,tag:203,remote:remote,bytes:32)
        let mode=UInt8(try r.integer(1)),front=try r.vector(),position=try r.vector(),z=try r.float()
        let packed=UInt8(try r.integer(1)),aspect=UInt8(try r.integer(1))
        let result=Aim(cameraMode:mode,front:front,position:position,aimZ:z,zoom:packed&63,weaponState:packed>>6,aspectRatio:aspect)
        try validate(result);return(result,sender)
    }
    private static func readBullet(_ data:Data,remote:Bool)throws->(Bullet,UInt16?) {
        var (r,sender)=try reader(data,tag:206,remote:remote,bytes:41)
        guard let kind=HitType(rawValue:UInt8(try r.integer(1)))else{throw Failure.invalid}
        let id=UInt16(try r.integer(2)),origin=try r.vector(),position=try r.vector(),offset=try r.vector(),weapon=UInt8(try r.integer(1))
        let result=Bullet(hitType:kind,hitID:id,origin:origin,position:position,offset:offset,weapon:weapon)
        try validate(result);return(result,sender)
    }
    static func clientAim(_ data:Data)throws->Aim{try readAim(data,remote:false).0}
    static func serverAim(_ data:Data)throws->Remote<Aim>{let(v,p)=try readAim(data,remote:true);return .init(player:p!,value:v)}
    static func clientBullet(_ data:Data)throws->Bullet{try readBullet(data,remote:false).0}
    static func serverBullet(_ data:Data)throws->Remote<Bullet>{let(v,p)=try readBullet(data,remote:true);return .init(player:p!,value:v)}
}
