// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Browser-world traffic is a separate typed channel. These records neither
/// create player roster entries nor imply server AI/authority or renderability.
enum NativeAmbientTrafficProtocol {
    typealias Failure=NativeAmbientPedestrianProtocol.Failure
    struct Identity:Equatable {let id:UInt16,model:UInt16,first:UInt8,second:UInt8}
    struct Leg:Equatable {let link:UInt16,lane:UInt8}
    struct Base:Equatable {
        let identity:Identity
        let first:Leg,second:Leg,next:Leg?
        let nextLane:UInt8
        let progress:Double,speed:Double,wanted:Double,rate:Double
    }
    struct More:Equatable {let id:UInt16,side:Double,aim:Double,health:Double,flags:UInt8}
    struct Free:Equatable {
        let id:UInt16
        let position:SIMD3<Double>,headingWire:Double,speed:Double,wanted:Double,rate:Double,turn:Double
    }
    struct Fast:Equatable {let id:UInt16,speed:Double,wanted:Double}
    struct Crew:Equatable {let id:UInt16,count:UInt8,deadSeats:UInt8}
    struct Ahead:Equatable {let id:UInt16,legs:[Leg]}
    struct Plate:Equatable {let id:UInt16,text:String}
    struct Shot:Equatable {let id:UInt16,weapon:UInt8,target:SIMD3<Double>,kind:UInt8}
    enum Event:Equatable {
        case base(atServerMilliseconds:Double,[Base])
        case gone([UInt16]),plates([Plate]),more([More]),shots([Shot]),crew([Crew]),ahead([Ahead])
        case free(atServerMilliseconds:Double,[Free])
        case fast([Fast])
        var count:Int {
            switch self {
            case .base(_,let v):return v.count
            case .gone(let v):return v.count
            case .plates(let v):return v.count
            case .more(let v):return v.count
            case .shots(let v):return v.count
            case .crew(let v):return v.count
            case .ahead(let v):return v.count
            case .free(_,let v):return v.count
            case .fast(let v):return v.count
            }
        }
    }
    static let maximumPayloadBytes=32767,maximumRecords=4096
    /// Complete outer records preceding an incomplete suffix remain usable,
    /// matching the observed browser dispatcher. Explicit resource caps are
    /// native admission policy; malformed lengths never index past a buffer.
    static func decodeMessage(_ data:Data,nowServerMilliseconds:Double)throws->[Event] {
        guard data.count<=1_048_576 else{throw Failure.limit}
        let bytes=Array(data);var cursor=0,frames=0,records=0,result:[Event]=[]
        while cursor+2<=bytes.count {
            frames+=1;guard frames<=maximumRecords else{throw Failure.limit}
            let tag=bytes[cursor],first=bytes[cursor+1];cursor+=2
            var length=Int(first)
            if first&128 != 0 {
                guard cursor<bytes.count else{break}
                length=Int(first&127)|(Int(bytes[cursor])<<7);cursor+=1
            }
            guard length<=bytes.count-cursor else{break}
            if let event=try decode(tag:tag,payload:Data(bytes[cursor..<cursor+length]),nowServerMilliseconds:nowServerMilliseconds) {
                records+=event.count;guard records<=maximumRecords else{throw Failure.limit};result.append(event)
            }
            cursor+=length
        }
        return result
    }
    /// Fixed-width consumers retain complete rows and ignore their partial
    /// tail; variable consumers stop at an incomplete declared record. The
    /// graph/state owner validates references and applies entity lifetimes.
    static func decode(tag:UInt8,payload:Data,nowServerMilliseconds:Double)throws->Event? {
        guard payload.count<=maximumPayloadBytes else{throw Failure.limit}
        guard [UInt8(4),5,6,9,31,33,34,36,37].contains(tag)else{return nil}
        let bytes=Array(payload),end=bytes.count
        func u16(_ at:Int)->UInt16{UInt16(bytes[at])<<8|UInt16(bytes[at+1])}
        func u32(_ at:Int)->UInt32{UInt32(bytes[at])<<24|UInt32(bytes[at+1])<<16|UInt32(bytes[at+2])<<8|UInt32(bytes[at+3])}
        func i32(_ at:Int)->Double{Double(Int32(bitPattern:u32(at)))}
        func fixed(_ start:Int,_ width:Int)throws->[Int] {
            guard start<=end else{return []}
            let count=(end-start)/width;guard count<=maximumRecords else{throw Failure.limit}
            return (0..<count).map{start+$0*width}
        }
        switch tag {
        case 4:
            guard end>=4 else{return nil}
            let at=try NativeAmbientPedestrianProtocol.recoverTime(u32(0),near:nowServerMilliseconds)
            let values=try fixed(4,19).map{at->Base in
                let lanes=u16(at+12),next=u16(at+10)
                return .init(identity:.init(id:u16(at),model:u16(at+2),first:bytes[at+4],second:bytes[at+5]),
                    first:.init(link:u16(at+6),lane:UInt8(lanes&15)),second:.init(link:u16(at+8),lane:UInt8(lanes>>4&15)),
                    next:next==65535 ? nil:.init(link:next,lane:UInt8(lanes>>8&15)),nextLane:UInt8(lanes>>8&15),progress:Double(u16(at+14))/65535,
                    speed:Double(bytes[at+16])/4,wanted:Double(bytes[at+17])/4,rate:Double(bytes[at+18])/16)
            };return .base(atServerMilliseconds:at,values)
        case 5:return .gone(try fixed(0,2).map{u16($0)})
        case 6:
            var cursor=0,values:[Plate]=[]
            while cursor+3<=end {
                let length=Int(bytes[cursor+2]);guard cursor+3+length<=end else{break}
                guard values.count<maximumRecords else{throw Failure.limit}
                // String.fromCharCode per byte, rather than UTF8 decoding.
                let scalars=bytes[(cursor+3)..<(cursor+3+length)].map{UnicodeScalar(UInt32($0))!}
                values.append(.init(id:u16(cursor),text:String(String.UnicodeScalarView(scalars))))
                cursor+=3+length
            };return .plates(values)
        case 9:return .more(try fixed(0,6).map{at in .init(id:u16(at),side:Double(Int8(bitPattern:bytes[at+2]))/16,
            aim:Double(Int8(bitPattern:bytes[at+3]))/16,health:Double(bytes[at+4])*4,flags:bytes[at+5])})
        case 31:return .shots(try fixed(0,18).map{at in .init(id:u16(at),weapon:bytes[at+2],
            target:SIMD3(i32(at+3)/1000,i32(at+7)/1000,i32(at+11)/1000),kind:bytes[at+15])})
        case 33:return .crew(try fixed(0,4).map{at in .init(id:u16(at),count:bytes[at+2],deadSeats:bytes[at+3])})
        case 34:
            var cursor=0,values:[Ahead]=[]
            while cursor+3<=end {
                let count=Int(bytes[cursor+2]);guard cursor+3+count*3<=end else{break}
                guard values.count<maximumRecords else{throw Failure.limit}
                let legs=(0..<count).map{index->Leg in let at=cursor+3+index*3;return .init(link:u16(at),lane:bytes[at+2])}
                values.append(.init(id:u16(cursor),legs:legs));cursor+=3+count*3
            };return .ahead(values)
        case 36:
            guard end>=4 else{return nil}
            let at=try NativeAmbientPedestrianProtocol.recoverTime(u32(0),near:nowServerMilliseconds)
            let values=try fixed(4,20).map{at in Free(id:u16(at),position:SIMD3(i32(at+2)/1000,i32(at+6)/1000,Double(Int16(bitPattern:u16(at+10)))/8),
                headingWire:Double(u16(at+12))/65536*(2*Double.pi),speed:Double(Int16(bitPattern:u16(at+14)))/64,
                wanted:Double(Int16(bitPattern:u16(at+16)))/64,rate:Double(bytes[at+18])/16,turn:Double(Int8(bitPattern:bytes[at+19]))/64)}
            return .free(atServerMilliseconds:at,values)
        case 37:return .fast(try fixed(0,6).map{at in .init(id:u16(at),speed:Double(u16(at+2))/64,wanted:Double(u16(at+4))/64)})
        default:return nil
        }
    }
}
