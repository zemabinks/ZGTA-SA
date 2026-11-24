import Foundation
import CryptoKit

/// Legacy SA-MP wire codecs, separate from the browser world's JSON protocol.
/// Protocol research: SA-MP-Pilot aa8c7971d2f3c8762a9f20c9ef35b42d5927a768
/// (Apache-2.0; attribution and license retained in native-samp).
enum NativeSAMPProtocol {
    enum Version: String, CaseIterable { case v037 = "0.3.7-R4", dl = "0.3.DL-R1"
        var number: UInt32 { self == .dl ? 4062:4057 }
    }
    enum Error: Swift.Error { case truncated, invalid, unsupported }
    struct Reader {
        let data: [UInt8]; let count: Int; var offset = 0
        init(_ data: Data, bits: Int? = nil) throws {
            guard data.count <= 1_048_576, bits == nil || (bits! >= 0 && bits! <= data.count*8) else { throw Error.invalid }
            self.data = Array(data); count = bits ?? data.count*8
        }
        var remaining: Int { count-offset }
        mutating func bit() throws -> Bool {
            guard offset < count else { throw Error.truncated }
            let value = data[offset/8] & (0x80 >> (offset%8)) != 0; offset += 1; return value
        }
        mutating func bytes(_ bits: Int, right: Bool = false) throws -> Data {
            guard bits >= 0, bits <= remaining else { throw Error.truncated }
            var output = [UInt8](repeating:0,count:(bits+7)/8)
            let shift = right && bits%8 != 0 ? 8-bits%8:0
            for i in 0..<bits { if try bit() { let j=i+shift; output[j/8] |= 0x80 >> (j%8) } }
            return Data(output)
        }
        mutating func integer(_ size: Int) throws -> UInt32 {
            guard (1...4).contains(size) else { throw Error.invalid }
            let bytes = try self.bytes(size*8); return bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset*8) }
        }
        mutating func float() throws -> Float { let value=Float(bitPattern:try integer(4)); guard value.isFinite else{throw Error.invalid};return value }
        mutating func vector() throws -> SIMD3<Float> { try SIMD3(float(),float(),float()) }
        mutating func text8() throws -> String { let n=Int(try integer(1));return Self.text(try bytes(n*8)) }
        static func text(_ bytes: Data) -> String { String(data:bytes,encoding:.windowsCP1252) ?? String(decoding:bytes,as:UTF8.self) }
        mutating func compressed(_ size: Int) throws -> UInt32 {
            guard size==2 || size==4 else{throw Error.invalid}
            var current=size-1
            while current>0 {if try bit(){current-=1}else{return try integer(current+1)}}
            let half=try bit(), raw=try bytes(half ? 4:8,right:true);return UInt32(raw.first ?? 0)
        }
        mutating func quaternion() throws -> SIMD4<Float> {
            let negativeW=try bit(),negativeX=try bit(),negativeY=try bit(),negativeZ=try bit()
            var x=Float(try integer(2))/65535,y=Float(try integer(2))/65535,z=Float(try integer(2))/65535
            if negativeX{x = -x};if negativeY{y = -y};if negativeZ{z = -z}
            var w=sqrt(max(0,1-x*x-y*y-z*z));if negativeW{w = -w}
            return SIMD4(w,x,y,z)
        }
        mutating func compressedVector() throws -> SIMD3<Float> {
            let length=try float();guard length>=0 else{throw Error.invalid};if length<=0.00001{return .zero}
            return try SIMD3((Float(integer(2))/32767.5-1)*length,(Float(integer(2))/32767.5-1)*length,(Float(integer(2))/32767.5-1)*length)
        }
    }
    struct Writer {
        private(set) var data = Data(); private(set) var bits = 0
        mutating func bit(_ value: Bool) { if bits/8==data.count{data.append(0)};if value{data[bits/8] |= 0x80 >> (bits%8)};bits+=1 }
        mutating func bytes(_ value: Data, bits count: Int? = nil, right: Bool = false) {
            let count=count ?? value.count*8;precondition(count>=0 && count<=value.count*8)
            let shift=right && count%8 != 0 ? 8-count%8:0
            for i in 0..<count {let j=i+shift;bit(value[j/8] & (0x80 >> (j%8)) != 0)}
        }
        mutating func integer(_ value: UInt32, size: Int) {precondition((1...4).contains(size));for i in 0..<size{bytes(Data([UInt8(truncatingIfNeeded:value >> (i*8))]))}}
        mutating func float(_ value: Float) {precondition(value.isFinite);integer(value.bitPattern,size:4)}
        mutating func vector(_ value: SIMD3<Float>){float(value.x);float(value.y);float(value.z)}
        mutating func text8(_ value: Data){precondition(value.count<=255);integer(UInt32(value.count),size:1);bytes(value)}
        mutating func compressed(_ value: UInt32,size: Int=4){
            precondition(size==2 || size==4);var current=size-1
            while current>0 {if value >> (current*8)==0{bit(true);current-=1}else{bit(false);integer(value,size:current+1);return}}
            if value&0xf0==0{bit(true);bytes(Data([UInt8(truncatingIfNeeded:value)]),bits:4,right:true)}else{bit(false);integer(value,size:1)}
        }
    }
    struct RPC {let id: UInt8;let data:Data;let bits:Int}
    static func rpc(_ id: UInt8, _ payload: Writer = Writer()) -> Data {
        var w=Writer();w.integer(20,size:1);w.integer(UInt32(id),size:1);w.compressed(UInt32(payload.bits));w.bytes(payload.data,bits:payload.bits);return w.data
    }
    static func rpc(_ data: Data) throws -> RPC {
        var input=data
        if input.first==40 {guard input.count>=6 else{throw Error.truncated};input=input.dropFirst(5)}
        var r=try Reader(input);guard try r.integer(1)==20 else{throw Error.unsupported}
        let id=UInt8(try r.integer(1)),count=Int(try r.compressed(4));guard count<=r.remaining else{throw Error.truncated}
        return try RPC(id:id,data:r.bytes(count),bits:count)
    }
    static func auth(_ challenge: Data) -> Data {
        let challenge=challenge.prefix(while:{$0 != 0});let digest=Array(Insecure.SHA1.hash(data:challenge))
        // XOR of the protocol transform table is 0x8c. The 20-byte operand is
        // part of the legacy authentication transform, not an access token.
        let code:[UInt8]=[0xff,0x25,0x34,0x39,0x4d,0,0x90,0x90,0x90,0x90,0x56,0x57,0x50,0x8b,0x44,0x24,0x14,0x8d,0x0c,0x80]
        var transformed:[UInt8]=[]
        for i in 0..<20 {let index=(i/4)*4+3-i%4;let first:UInt8=digest[index] ^ UInt8(0x8c);transformed.append(first ^ code[i])}
        let text=transformed.map{String(format:"%02X",$0)}.joined();return Data([12,UInt8(text.utf8.count)])+Data(text.utf8)
    }
    static func installationID(source: Data) throws -> String {
        guard source.count==20,source.allSatisfy({(48...57).contains($0)||(65...90).contains($0)})else{throw Error.invalid}
        var result=[UInt8](source),carry=0
        for i in result.indices.reversed(){let n=Int(result[i])*1001+carry;result[i]=UInt8(n&255);carry=n>>8}
        while carry>0{result.insert(UInt8(carry&255),at:0);carry >>= 8}
        return result.map{String(format:"%02X",$0)}.joined().drop(while:{$0=="0"}).description
    }
    static func join(version: Version,nickname:String,installationID:String,challenge:UInt32)throws->Data {
        let name=Data(nickname.utf8),identity=Data(installationID.utf8)
        guard (3...24).contains(name.count),name.allSatisfy({(33...126).contains($0)}),
              (1...64).contains(identity.count),identity.allSatisfy({(48...57).contains($0)||(65...70).contains($0)})else{throw Error.invalid}
        var w=Writer();w.integer(version.number,size:4);w.integer(1,size:1);w.text8(name);w.integer(challenge^version.number,size:4);w.text8(identity);w.text8(Data(version.rawValue.utf8));return rpc(25,w)
    }
    struct Foot {
        var position: SIMD3<Float>;var heading: Float;var velocity=SIMD3<Float>.zero
        var health:UInt8=100,armour:UInt8=0,weapon:UInt8=0,action:UInt8=0
        var specialKeys:UInt8=0
        var keys:UInt16=0,lr:Int16=0,ud:Int16=0,animation:UInt16=0,animationFlags:UInt16=0
        var support:UInt16=0,supportOffset=SIMD3<Float>.zero
    }
    /// GTA/native heading grows clockwise from north; SA-MP's Z quaternion
    /// grows counter-clockwise. Convert once at this transport boundary.
    static func onFoot(_ frame:Foot)throws->Data {
        guard [frame.position,frame.velocity,frame.supportOffset].allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}),frame.heading.isFinite,frame.weapon<=46,frame.specialKeys<=3 else{throw Error.invalid}
        var w=Writer();w.integer(207,size:1);w.integer(UInt32(UInt16(bitPattern:frame.lr)),size:2);w.integer(UInt32(UInt16(bitPattern:frame.ud)),size:2);w.integer(UInt32(frame.keys),size:2);w.vector(frame.position)
        w.float(cos(frame.heading/2));w.float(0);w.float(0);w.float(-sin(frame.heading/2))
        for value in [frame.health,frame.armour,frame.weapon | (frame.specialKeys << 6),frame.action]{w.integer(UInt32(value),size:1)}
        w.vector(frame.velocity);w.vector(frame.supportOffset);w.integer(UInt32(frame.support),size:2);w.integer(UInt32(frame.animation),size:2);w.integer(UInt32(frame.animationFlags),size:2);return w.data
    }
    struct Spawn {let team:UInt8;let skin:Int32;let customSkin:Int32?;let position:SIMD3<Float>;let heading:Float;var weapons:[(Int,Int)]=[]}
    static func spawn(_ r:inout Reader,version:Version)throws->Spawn {
        let team=UInt8(try r.integer(1)),skin=Int32(bitPattern:try r.integer(4));let custom=version == .dl ? Int32(bitPattern:try r.integer(4)):nil
        _=try r.integer(1);let position=try r.vector(),degrees=try r.float()
        var spawn=Spawn(team:team,skin:skin,customSkin:custom,position:position,heading:-degrees * .pi/180)
        if r.remaining>=192 {
            var ids:[Int]=[],ammo:[Int]=[]
            for _ in 0..<3{ids.append(Int(try r.integer(4)))}
            for _ in 0..<3{ammo.append(Int(try r.integer(4)))}
            for i in 0..<3 where (1...46).contains(ids[i]){spawn.weapons.append((ids[i],ammo[i]))}
        }
        return spawn
    }
    struct Introduction {
        let id:UInt16;let classes:Int;let hour:Int;let weather:Int;let gravity:Float
        var footMilliseconds=30,carMilliseconds=30,weaponMilliseconds=30
    }
    static func introduction(_ r:inout Reader)throws->Introduction {
        for _ in 0..<4{_=try r.bit()};_=try r.float();_=try r.bit();_=try r.float()
        for _ in 0..<3{_=try r.bit()};let classes=Int(try r.integer(4)),id=UInt16(try r.integer(2))
        guard classes<=10000 else{throw Error.invalid};_=try r.bit();_=try r.integer(4)
        let hour=Int(try r.integer(1)),weather=Int(try r.integer(1)),gravity=try r.float()
        guard hour<24 else{throw Error.invalid}
        var result=Introduction(id:id,classes:classes,hour:hour,weather:weather,gravity:gravity)
        if r.remaining>7 {
            _=try r.bit();_=try r.integer(4);_=try r.bit()
            func interval(_ value:UInt32)->Int{value==0 ? 30:max(10,min(1000,Int(value)))}
            result.footMilliseconds=interval(try r.integer(4));result.carMilliseconds=interval(try r.integer(4));result.weaponMilliseconds=interval(try r.integer(4))
        }
        return result
    }
    static func localID(_ r:inout Reader)throws->UInt16 {
        for _ in 0..<4{_=try r.bit()};_=try r.float();_=try r.bit();_=try r.float()
        for _ in 0..<3{_=try r.bit()};_=try r.integer(4);return UInt16(try r.integer(2))
    }
    /// Convert a GTA Z-up quaternion (w,x,y,z) into the native renderer's
    /// YXZ presentation angles. Preserve full vehicle pitch/roll over the wire.
    static func nativeAngles(_ gta:SIMD4<Float>)->(heading:Float,pitch:Float,roll:Float){
        let w=Double(gta.x),x=Double(gta.y),y=Double(gta.w),z = -Double(gta.z)
        let m23=2*(y*z-w*x),pitch=asin(-min(1,max(-1,m23)))
        if abs(m23)<0.9999999 {
            return(-Float(atan2(2*(x*z+w*y),1-2*(x*x+y*y))),Float(pitch),-Float(atan2(2*(x*y+w*z),1-2*(x*x+z*z))))
        }
        return(-Float(atan2(-2*(x*z-w*y),1-2*(y*y+z*z))),Float(pitch),0)
    }
    struct Car {
        var id:UInt16;var position:SIMD3<Float>;var quaternion:SIMD4<Float>
        var velocity=SIMD3<Float>.zero;var health:Float=1000
        var playerHealth:UInt8=100,armour:UInt8=0,weapon:UInt8=0,siren:UInt8=0,gear:UInt8=0
        var specialKeys:UInt8=0
        var lr:Int16=0,ud:Int16=0,keys:UInt16=0,trailer:UInt16=0;var trainSpeed:Float=0
    }
    static func car(_ frame:Car)throws->Data {
        guard frame.id>0,frame.health.isFinite,frame.trainSpeed.isFinite,frame.weapon<=46,frame.specialKeys<=3,
              [frame.position,frame.velocity].allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}),
              [frame.quaternion.x,frame.quaternion.y,frame.quaternion.z,frame.quaternion.w].allSatisfy(\.isFinite)else{throw Error.invalid}
        var w=Writer();w.integer(200,size:1);w.integer(UInt32(frame.id),size:2)
        for v in [UInt16(bitPattern:frame.lr),UInt16(bitPattern:frame.ud),frame.keys]{w.integer(UInt32(v),size:2)}
        for v in [frame.quaternion.x,frame.quaternion.y,frame.quaternion.z,frame.quaternion.w]{w.float(v)}
        w.vector(frame.position);w.vector(frame.velocity);w.float(frame.health)
        for v in [frame.playerHealth,frame.armour,frame.weapon | (frame.specialKeys << 6),frame.siren,frame.gear]{w.integer(UInt32(v),size:1)}
        w.integer(UInt32(frame.trailer),size:2);w.float(frame.trainSpeed);return w.data
    }
    struct RemotePassenger {
        let playerID: UInt16
        let vehicleID: UInt16
        let seat: Int
        let health: Int
        let armour: Int
        let weapon: Int
        let position: SIMD3<Float>
    }

    static func passenger(vehicleID: UInt16, seat: Int, position: SIMD3<Float>,
                          health: UInt8, armour: UInt8) throws -> Data {
        guard vehicleID > 0, (1...63).contains(seat),
              [position.x, position.y, position.z].allSatisfy(\.isFinite) else { throw Error.invalid }
        var writer = Writer()
        writer.integer(211, size: 1)
        writer.integer(UInt32(vehicleID), size: 2)
        writer.integer(UInt32(seat), size: 2)
        writer.integer(UInt32(health), size: 1)
        writer.integer(UInt32(armour), size: 1)
        for _ in 0..<3 { writer.integer(0, size: 2) } // No drive-by controls.
        writer.vector(position)
        return writer.data
    }

    /// Server broadcast layout from open.mp v1.6.7.3218 Shared/NetCode/vehicle.hpp.
    static func remotePassenger(_ data: Data) throws -> RemotePassenger {
        var reader = try Reader(data)
        guard try reader.integer(1) == 211 else { throw Error.unsupported }
        let playerID = UInt16(try reader.integer(2))
        let vehicleID = UInt16(try reader.integer(2))
        let flags = try reader.integer(2)
        let seat = Int(flags & 0x3f)
        guard vehicleID > 0, seat > 0 else { throw Error.invalid }
        let health = Int(try reader.integer(1))
        let armour = Int(try reader.integer(1))
        for _ in 0..<3 { _ = try reader.integer(2) } // LR, UD and keys.
        let position = try reader.vector()
        guard reader.remaining == 0 else { throw Error.invalid }
        return RemotePassenger(playerID: playerID, vehicleID: vehicleID, seat: seat,
                               health: health, armour: armour, weapon: Int((flags >> 8) & 0x3f),
                               position: position)
    }

    static func bullet(weapon:Int,origin:SIMD3<Float>,hit:SIMD3<Float>,target:UInt16?,offset:SIMD3<Float> = .zero)throws->Data{
        guard (0...46).contains(weapon),[origin,hit,offset].allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite})else{throw Error.invalid}
        var w=Writer();w.integer(206,size:1);w.integer(target == nil ? 0:1,size:1);w.integer(UInt32(target ?? 65535),size:2)
        w.vector(origin);w.vector(hit);w.vector(offset);w.integer(UInt32(weapon),size:1);return w.data
    }
    static func damage(taking:Bool,player:UInt16,amount:Float,weapon:Int,body:Int=3)throws->Data{
        guard amount.isFinite,amount>0,amount<=10000,(0...54).contains(weapon),(3...9).contains(body)else{throw Error.invalid}
        var w=Writer();w.bit(taking);w.integer(UInt32(player),size:2);w.float(amount);w.integer(UInt32(weapon),size:4);w.integer(UInt32(body),size:4);return rpc(115,w)
    }
}
