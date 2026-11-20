// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Typed nonplayer records from the browser's separate pedestrian channel.
/// It does not create player rows, select AI goals or authorize damage.
enum NativeAmbientPedestrianProtocol {
    enum Failure: Error {case malformed,limit,unsupportedClock}
    struct Identity: Equatable {let id:UInt16,skin:UInt16;let flags:UInt8,seed:UInt8}
    struct Free: Equatable {
        let identity:Identity
        let feet:SIMD3<Double>,goal:SIMD2<Double>
        let speed:Double,desiredSpeed:Double
    }
    struct Path: Equatable {
        let identity:Identity
        let from:UInt16,to:UInt16,next:UInt16?
        let progress:Double,speed:Double,desiredSpeed:Double,side:Double,desiredSide:Double
    }
    struct State: Equatable {
        let id:UInt16,mood:UInt8
        let burning:Bool,phone:Bool,crouching:Bool,cpr:Bool
        let weapon:UInt8,hitWeapon:UInt8,hitCounter:UInt8,hitPiece:UInt8
        let hitFromWire:Double,faceWire:Double
        let foe:UInt16,thrown:Double
    }
    enum Event: Equatable {
        case free(atServerMilliseconds:Double,[Free])
        case path(atServerMilliseconds:Double,[Path])
        case gone([UInt16])
        case state([State])
    }
    static let maximumPayloadBytes=32767
    static let maximumRecords=4096

    /// This clock is explicitly in the server epoch domain, separate from
    /// local monotonic receipt/animation clocks. Half-wrap ambiguity is part
    /// of the32-bit wire format; staleness admission belongs to the owner.
    static func recoverTime(_ stamp:UInt32,near now:Double)throws->Double {
        guard now.isFinite,now>=0,now<=9_007_199_254_740_991 else{throw Failure.unsupportedClock}
        let cycle=4_294_967_296.0,half=2_147_483_648.0
        var age=(now.truncatingRemainder(dividingBy:cycle)-Double(stamp)+half).truncatingRemainder(dividingBy:cycle)
        if age<0{age+=cycle}
        return now-(age-half)
    }

    /// Own-server binary admission uses this bounded outer container only
    /// after capability negotiation. Original-world connections can retain
    /// their existing demultiplexer and call decode(tag:payload:) directly.
    /// Unknown subsystem bodies are skipped, never treated as player rows.
    static func decodeMessage(_ data:Data,nowServerMilliseconds:Double)throws->[Event] {
        guard data.count<=1_048_576 else{throw Failure.limit}
        let bytes=Array(data);var cursor=0,records=0,actors=0,result:[Event]=[]
        while cursor<bytes.count {
            records+=1;guard records<=maximumRecords,cursor+2<=bytes.count else{throw Failure.malformed}
            let tag=bytes[cursor],first=bytes[cursor+1];cursor+=2
            var length=Int(first)
            if first&128 != 0 {
                guard cursor<bytes.count else{throw Failure.malformed}
                length=Int(first&127)|(Int(bytes[cursor])<<7);cursor+=1
            }
            guard length<=bytes.count-cursor else{throw Failure.malformed}
            let body=Data(bytes[cursor..<cursor+length]);cursor+=length
            if let event=try decode(tag:tag,payload:body,nowServerMilliseconds:nowServerMilliseconds) {
                switch event {
                case .free(_,let values):actors+=values.count
                case .path(_,let values):actors+=values.count
                case .gone(let values):actors+=values.count
                case .state(let values):actors+=values.count
                }
                guard actors<=maximumRecords else{throw Failure.limit}
                result.append(event)
            }
        }
        return result
    }

    /// The existing connection first admits the outer framed record and its
    /// session. Decode a whole typed record before publishing any actors.
    /// Other channels remain explicit extensions for their respective owners.
    static func decode(tag:UInt8,payload:Data,nowServerMilliseconds:Double)throws->Event? {
        guard payload.count<=maximumPayloadBytes else{throw Failure.limit}
        guard [UInt8(7),8,10,11].contains(tag)else{return nil}
        let bytes=Array(payload)
        func u16(_ at:Int)->UInt16{UInt16(bytes[at])<<8|UInt16(bytes[at+1])}
        func i16(_ at:Int)->Int16{Int16(bitPattern:u16(at))}
        func u32(_ at:Int)->UInt32{UInt32(bytes[at])<<24|UInt32(bytes[at+1])<<16|UInt32(bytes[at+2])<<8|UInt32(bytes[at+3])}
        func i32(_ at:Int)->Int32{Int32(bitPattern:u32(at))}
        func identity(_ at:Int)->Identity {
            let packed=u16(at+2)
            return .init(id:u16(at),skin:packed&4095,flags:UInt8(packed>>12),seed:bytes[at+4])
        }
        let prefix=(tag==7 || tag==10) ? 4:0
        let stride=tag==7 ? 17:tag==10 ? 21:tag==8 ? 2:11
        guard bytes.count>=prefix,(bytes.count-prefix)%stride==0 else{throw Failure.malformed}
        let count=(bytes.count-prefix)/stride
        guard count<=maximumRecords else{throw Failure.limit}
        var seen=Set<UInt16>()
        for at in Swift.stride(from:prefix,to:bytes.count,by:stride) {
            guard seen.insert(u16(at)).inserted else{throw Failure.malformed}
        }
        if tag==8 {
            return .gone(Swift.stride(from:0,to:bytes.count,by:2).map{u16($0)})
        }
        if tag==11 {
            let values=Swift.stride(from:0,to:bytes.count,by:11).map { at->State in
                let mode=bytes[at+2],hit=bytes[at+6],piece=hit>>5
                return .init(id:u16(at),mood:mode&15,burning:mode&16 != 0,phone:mode&32 != 0,
                    crouching:mode&64 != 0,cpr:mode&128 != 0,weapon:bytes[at+3],hitWeapon:bytes[at+4],
                    hitCounter:hit&31,hitPiece:piece==0 ? 0:piece+2,
                    hitFromWire:Double(bytes[at+5]) * .pi/128,faceWire:Double(bytes[at+7]) * .pi/128,
                    foe:u16(at+8),thrown:Double(bytes[at+10])/4)
            }
            return .state(values)
        }
        let time=try recoverTime(u32(0),near:nowServerMilliseconds)
        if tag==10 {
            let values=Swift.stride(from:4,to:bytes.count,by:21).map { at->Free in
                let x=Double(i32(at+5))/1000,y=Double(i32(at+9))/1000
                return .init(identity:identity(at),feet:SIMD3(x,y,Double(i16(at+13))/8),
                    goal:SIMD2(x+Double(i16(at+15))/16,y+Double(i16(at+17))/16),
                    speed:Double(bytes[at+19])/32,desiredSpeed:Double(bytes[at+20])/32)
            }
            return .free(atServerMilliseconds:time,values)
        }
        let values=Swift.stride(from:4,to:bytes.count,by:17).map { at->Path in
            let next=u16(at+9)
            return .init(identity:identity(at),from:u16(at+5),to:u16(at+7),next:next==65535 ? nil:next,
                progress:Double(u16(at+11))/65535,speed:Double(bytes[at+13])/32,
                desiredSpeed:Double(bytes[at+14])/32,side:Double(Int8(bitPattern:bytes[at+15]))/16,
                desiredSide:Double(Int8(bitPattern:bytes[at+16]))/16)
        }
        return .path(atServerMilliseconds:time,values)
    }
}
