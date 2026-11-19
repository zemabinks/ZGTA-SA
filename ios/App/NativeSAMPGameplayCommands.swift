// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Independently written codecs for official open.mp Shared/NetCode/core.hpp
/// 2b4a69dd606dc2f93e98b0f1ffe8801cc01633f5. Camera/spectator positions are
/// physical GTA world coordinates, never pedestrian model roots or feet.
enum NativeSAMPGameplayCommands {
    enum Cut:UInt8,Equatable {case move=1,cut=2}
    enum SpectateMode:UInt8,Equatable {case normal=1,fixed=2,side=3}
    enum Command:Equatable {
        case reset
        case controllable(Bool)
        case gravity(Float)
        case cameraPosition(SIMD3<Float>)
        case cameraLookAt(SIMD3<Float>,Cut)
        case cameraBehind
        case cameraInterpolation(position:Bool,from:SIMD3<Float>,to:SIMD3<Float>,milliseconds:UInt32,cut:Cut)
        case spectating(Bool)
        case spectatePlayer(UInt16,SpectateMode)
        case spectateVehicle(UInt16,SpectateMode)
    }
    struct Event:Equatable {
        let generation:UInt64,sequence:UInt64
        let command:Command
    }
    /// One input owner; stale generations, reordered/duplicate callbacks and
    /// stale resets cannot unfreeze or retarget a replacement session.
    struct Authority {
        private(set) var generation:UInt64?,sequence:UInt64=0
        private(set) var controllable=true,spectating=false
        private(set) var gravity:Float?
        var inputBlocked:Bool{!controllable || spectating}
        @discardableResult mutating func apply(_ event:Event)->Bool {
            if event.command == .reset {
                guard generation==nil || event.generation>generation!,event.sequence==0 else{return false}
                generation=event.generation;sequence=0;controllable=true;spectating=false;gravity=nil;return true
            }
            guard generation==event.generation,event.sequence>sequence else{return false}
            if case .gravity(let value)=event.command,!NativeSAMPGameplayCommands.validGravity(value){return false}
            sequence=event.sequence
            switch event.command {case .controllable(let value):controllable=value
            case .spectating(let value):spectating=value
            case .gravity(let value):gravity=value
            default:break}
            return true
        }
    }
    /// Explicit simulation policy matching the documented signed open.mp range.
    /// Reject unsupported values without silently clamping the server operand.
    static func validGravity(_ value:Float)->Bool{value.isFinite && abs(value)<=50}
    static func decode(_ rpc:NativeSAMPProtocol.RPC)throws->Command? {
        var reader=try NativeSAMPProtocol.Reader(rpc.data,bits:rpc.bits)
        func boolean(_ bytes:Int)throws->Bool{let value=try reader.integer(bytes);guard value<=1 else{throw NativeSAMPProtocol.Error.invalid};return value==1}
        func cut()throws->Cut{guard let value=Cut(rawValue:UInt8(try reader.integer(1)))else{throw NativeSAMPProtocol.Error.invalid};return value}
        func target(vehicle:Bool)throws->(UInt16,SpectateMode){
            let id=UInt16(try reader.integer(2));guard id != 65535,(!vehicle || id>0),let mode=SpectateMode(rawValue:UInt8(try reader.integer(1)))else{throw NativeSAMPProtocol.Error.invalid};return(id,mode)
        }
        let command:Command
        switch rpc.id {
        case 146:
            let value=try reader.float();guard validGravity(value)else{throw NativeSAMPProtocol.Error.invalid}
            command = .gravity(value)
        case 15:command = .controllable(try boolean(1))
        case 157:command = .cameraPosition(try reader.vector())
        case 158:let point=try reader.vector();command = .cameraLookAt(point,try cut())
        case 162:command = .cameraBehind
        case 82:
            let position=try reader.bit(),from=try reader.vector(),to=try reader.vector(),duration=try reader.integer(4)
            guard duration<=UInt32(Int32.max)else{throw NativeSAMPProtocol.Error.invalid}
            command = .cameraInterpolation(position:position,from:from,to:to,milliseconds:duration,cut:try cut())
        case 124:command = .spectating(try boolean(4))
        case 126:let(id,mode)=try target(vehicle:false);command = .spectatePlayer(id,mode)
        case 127:let(id,mode)=try target(vehicle:true);command = .spectateVehicle(id,mode)
        default:return nil
        }
        guard reader.remaining==0 else{throw NativeSAMPProtocol.Error.invalid};return command
    }
    static func spectator(position:SIMD3<Float>,keys:UInt16=0,axes:SIMD2<Int16> = .zero)throws->Data {
        guard [position.x,position.y,position.z].allSatisfy(\.isFinite),abs(Int(axes.x))<=128,abs(Int(axes.y))<=128 else{throw NativeSAMPProtocol.Error.invalid}
        var writer=NativeSAMPProtocol.Writer();writer.integer(212,size:1)
        writer.integer(UInt32(UInt16(bitPattern:axes.x)),size:2);writer.integer(UInt32(UInt16(bitPattern:axes.y)),size:2)
        writer.integer(UInt32(keys),size:2);writer.vector(position);return writer.data
    }
}
