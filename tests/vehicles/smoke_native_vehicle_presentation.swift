// SPDX-License-Identifier: AGPL-3.0-only
// Entirely authored CPU fixtures. No original meshes, palette, tables or
// recorded gameplay samples are embedded in this gate.
import Foundation
import simd
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class PresentationClock {
    static let processInfo=PresentationClock()
    var systemUptime=10.0
}

@main enum VehiclePresentationGate {
    struct Failure:Error,CustomStringConvertible {let description:String}
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws {
        checks+=1;if !value{throw Failure(description:message)}
    }
    static func close(_ a:Double,_ b:Double,_ message:String,tolerance:Double=1e-9)throws {
        try check(a.isFinite && b.isFinite && abs(a-b)<tolerance,message+" (\(a) versus \(b))")
    }
    static func matrix(_ a:simd_double4x4,_ b:simd_double4x4,_ message:String)throws {
        for column in 0..<4 {for row in 0..<4 {try close(a[column][row],b[column][row],message)}}
    }
    static func main(){
        do {try run();print("PASS authored vehicle presentation: \(checks) checks; literal renderer, remote aircraft defaults, explicit source precedence, parked phase, owner clocks and retained cap")}
        catch {fputs("FAIL \(error)\n",stderr);exit(1)}
    }
    static func run()throws {
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let document=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        let rigRows=document["rigs"] as! [String:[String:Any]]
        var rigs:[String:NativeVehicleRig]=[:]
        for (kind,row) in rigRows {
            let bytes=try JSONSerialization.data(withJSONObject:row)
            guard let rig=NativeVehicleRig(data:bytes)else{throw Failure(description:"Authored rig schema rejected: \(kind)")}
            rigs[kind]=rig
        }
        guard let suspension=NativeRemoteSuspension.Configuration(document["suspension"] as! [String:Any])else{throw Failure(description:"Authored suspension schema")}
        typealias H=VehiclePresentationHarness
        func context(_ source:H.VehicleDrawContext.Source,_ token:String,code:String="400.1.0")->H.VehicleDrawContext {
            .init(source:source,token:token,appearanceCode:code,roll:0,origin:0,exactTransform:nil,heldDoorID:nil)
        }
        func remote(_ token:String,speed:Float=0)->H.VehicleDrawContext {
            var player=H.RemotePlayer(id:token);player.speed=speed
            return context(.remote(player),token)
        }
        func own(_ token:String,rotor:Double,gearUp:Bool=false)->H.VehicleDrawContext {
            var input=NativeVehicleRig.Input();input.rotor=rotor;input.gearUp=gearUp
            let state=H.OwnVehicleDrawSnapshot(input:input,doors:nil,wheelOffsets:[:],wheelAngles:[],speed:0,steering:0,rearSteering:0,fallbackSteering:0)
            return context(.own(state),token)
        }
        func parked(_ token:String,rotor:Double,dynamic:Bool,front:Double=0,rear:Double=0,offsets:[Double]=[])->H.VehicleDrawContext {
            let sample=H.ParkedVehicleDrawSnapshot(work:0,rotor:rotor,gearUp:false,dynamic:dynamic,frontSpin:front,rearSpin:rear,offsets:offsets)
            return context(.parked(H.RemoteVehicle(),sample),token)
        }
        @discardableResult func draw(_ host:H,_ kind:String,_ source:H.VehicleDrawContext,_ time:Double)->NativeVehicleRig.Frame {
            PresentationClock.processInfo.systemUptime=time
            return host.vehicleRigFrame(position:.zero,modelTransform:matrix_identity_float4x4,rig:rigs[kind]!,context:source)
        }
        func rotorMatrix(_ phase:Double)->simd_double4x4 {
            simd_double4x4(simd_quatd(angle:-phase,axis:SIMD3(0,0,1)))
        }
        // The first assertion is intentionally the historical rejection oracle.
        let heli=H(),heliSource=remote("heli")
        draw(heli,"heli",heliSource,10);let heliFrame=draw(heli,"heli",heliSource,10.1)
        try close(heli.vehicleRigStates["heli"]!.rotorSpin,1.1,"remote helicopter presentation default")
        try matrix(heliFrame.matrices[1],rotorMatrix(1.1),"remote helicopter rotor matrix")
        let plane=H(),planeSource=remote("plane")
        draw(plane,"plane",planeSource,10);let planeFrame=draw(plane,"plane",planeSource,10.1)
        try close(plane.vehicleRigStates["plane"]!.rotorSpin,0.9,"remote plane presentation default")
        try matrix(planeFrame.matrices[1],rotorMatrix(0.9),"remote plane rotor matrix")
        // Paint is real production decoding on an authored black/white palette.
        try check(heliFrame.draws.first?.paint==SIMD4<Float>(1,1,1,1),"actual paint source did not consume authored appearance")
        for kind in ["heli","plane"] {
            for rate in [0.0,0.07] {
                for source in [own("explicit",rotor:rate),parked("explicit",rotor:rate,dynamic:true),parked("explicit",rotor:rate,dynamic:false)] {
                    let host=H();draw(host,kind,source,10);let frame=draw(host,kind,source,10.1)
                    try close(host.vehicleRigStates["explicit"]!.rotorSpin,rate*5,"explicit own/parked rotor precedence")
                    try matrix(frame.matrices[1],rotorMatrix(rate*5),"explicit rotor matrix precedence")
                }
            }
            let host=H(),unowned=context(.parked(H.RemoteVehicle(),nil),"no-physical")
            draw(host,kind,unowned,10);draw(host,kind,unowned,10.1)
            try close(host.vehicleRigStates["no-physical"]!.rotorSpin,0,"parked source without sample invented an active rotor")
        }
        for kind in ["car","boat","bike","train"] {
            let host=H(),source=remote("unrelated")
            draw(host,kind,source,10);let frame=draw(host,kind,source,10.1)
            try close(host.vehicleRigStates["unrelated"]!.rotorSpin,0,"unrelated vehicle kind gained aircraft clock")
            try matrix(frame.matrices[1],matrix_identity_double4x4,"unrelated rotor node changed")
        }
        // Keep the existing 100ms cap at both the renderer and rig boundary.
        let capped=H();var capPlayer=H.RemotePlayer(id:"cap");capPlayer.kit=[0,0,0,0,0,0,1]
        let capSource=context(.remote(capPlayer),"cap")
        draw(capped,"heli",capSource,10);draw(capped,"heli",capSource,10.35)
        try close(capped.vehicleRigStates["cap"]!.rotorSpin,1.1,"retained renderer/rig cap changed")
        try close(capped.vehicleRigStates["cap"]!.gearShare,0.1,"retained gear cap changed")
        let wheels=H(),wheelSource=remote("wheel-cap",speed:9)
        draw(wheels,"car",wheelSource,10);draw(wheels,"car",wheelSource,10.35)
        try close(wheels.vehicleRigSpins["wheel-cap"]!.x,-9*0.1/0.36,"retained wheel phase cap changed")
        // A physical parked sample owns its phase even after solver demotion.
        let parkedHost=H();parkedHost.remoteSuspensionConfigurations[400]=suspension
        parkedHost.query={ray in .hit(distance:ray.distance/2,normal:SIMD3(0,0,1))}
        let dynamic=parked("parked",rotor:0,dynamic:true,front:0.7,rear:-1.1,offsets:[0.15,0.15,0,0])
        let first=draw(parkedHost,"car",dynamic,10)
        try check(parkedHost.queryCount==0,"physical suspension lost precedence")
        let demoted=parked("parked",rotor:0,dynamic:false,front:0.7,rear:-1.1)
        let second=draw(parkedHost,"car",demoted,10.05)
        try check(parkedHost.queryCount==2,"demoted suspension did not use the actual projection helper")
        try matrix(first.matrices[2],second.matrices[2],"front wheel matrix jumped on demotion")
        try matrix(first.matrices[3],second.matrices[3],"rear wheel matrix jumped on demotion")
        try close(parkedHost.vehicleRigSpins["parked"]!.x,0.7,"front phase cache ignored physical sample")
        try close(parkedHost.vehicleRigSpins["parked"]!.y,-1.1,"rear phase cache ignored physical sample")
        let fallback=context(.parked(H.RemoteVehicle(),nil),"parked")
        let third=draw(parkedHost,"car",fallback,10.1)
        try matrix(second.matrices[2],third.matrices[2],"front fallback cache forgot parked phase")
        try matrix(second.matrices[3],third.matrices[3],"rear fallback cache forgot parked phase")
        // Existing owner-token partition must isolate clocks, phase and paint.
        let owners=H(),ownerA=remote("A"),ownerB=remote("B")
        draw(owners,"heli",ownerA,10);draw(owners,"heli",ownerA,10.1)
        let savedA=owners.vehicleRigStates["A"]!.rotorSpin
        draw(owners,"heli",ownerB,10.1)
        try close(owners.vehicleRigStates["B"]!.rotorSpin,0,"new token inherited another owner's elapsed")
        draw(owners,"heli",ownerB,10.15)
        try close(owners.vehicleRigStates["B"]!.rotorSpin,0.55,"owner B phase")
        try close(owners.vehicleRigStates["A"]!.rotorSpin,savedA,"owner B mutated owner A phase")
        try close(owners.vehicleRigTimes["A"]!,10.1,"owner B mutated owner A clock")
        let phaseA=parked("phase-A",rotor:0,dynamic:false,front:0.31,rear:0.52)
        let phaseB=parked("phase-B",rotor:0,dynamic:false,front:-0.4,rear:0.2)
        draw(owners,"car",phaseA,10.2);draw(owners,"car",phaseB,10.2)
        try close(owners.vehicleRigSpins["phase-A"]!.x,0.31,"owner A wheel phase isolation")
        try close(owners.vehicleRigSpins["phase-B"]!.x,-0.4,"owner B wheel phase isolation")
        let black=context(.remote(H.RemotePlayer(id:"black")),"black",code:"400.0.1")
        let blackFrame=draw(owners,"car",black,10.2)
        try check(blackFrame.draws.first?.paint==SIMD4<Float>(0,0,0,1),"authored owner paint isolation")
        // Exercise actual damage decoding and resulting rig wheel visibility.
        var damaged=H.RemotePlayer(id:"damaged");var wire=Array(repeating:"0",count:19);wire[15]="2";damaged.vehicleDamage=wire.joined()
        let damagedFrame=draw(owners,"car",context(.remote(damaged),"damaged"),10.2)
        try check(!damagedFrame.visible[2] && damagedFrame.visible[3],"actual damage/rig tyre visibility boundary")
    }
}
