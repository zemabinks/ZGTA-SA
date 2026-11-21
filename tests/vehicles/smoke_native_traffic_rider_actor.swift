// SPDX-License-Identifier: AGPL-3.0-only
// Authored SKN1/CLP1 inputs exercise the complete production decoder, raw poser
// and traffic adapter. Metal allocates buffers; this is not a rendered scene.
import Foundation
import Metal
import simd
private var checks=0
private func check(_ value:Bool,_ message:String){precondition(value,message);checks+=1}
private extension Data {
    mutating func u32(_ value:UInt32){var value=value.littleEndian;Swift.withUnsafeBytes(of:&value){append(contentsOf:$0)}}
    mutating func i32(_ value:Int32){u32(UInt32(bitPattern:value))}
    mutating func f32(_ value:Float){u32(value.bitPattern)}
    mutating func string(_ value:String){var count=UInt16(value.utf8.count).littleEndian;Swift.withUnsafeBytes(of:&count){append(contentsOf:$0)};append(contentsOf:value.utf8)}
    mutating func vector(_ value:SIMD3<Float>){f32(value.x);f32(value.y);f32(value.z)}
    mutating func matrix(_ value:simd_float4x4){for c in 0..<4{for r in 0..<4{f32(value[c][r])}}}
}
private func translated(_ point:SIMD3<Float>)->simd_float4x4{var value=matrix_identity_float4x4;value.columns.3=SIMD4(point,1);return value}
private func skeleton(rootOffset:Float=0)->Data {
    var data=Data();data.u32(0x314e4b53);data.u32(2);data.u32(3);data.u32(3)
    data.matrix(matrix_identity_float4x4);data.matrix(matrix_identity_float4x4)
    for (parent,bone,point) in [(-1,0,SIMD3<Float>(0,0,rootOffset)),(0,1,SIMD3(0,0,0.5)),(1,24,SIMD3(0.2,0,0.4))] {
        data.i32(Int32(parent));data.i32(Int32(bone));data.matrix(translated(point))
    }
    for frame in 0..<3{data.u32(UInt32(frame));data.matrix(matrix_identity_float4x4)}
    for bone in [UInt8(0),1] {
        data.vector(SIMD3(0.1,0.2,0.3));data.append(contentsOf:[bone,0,0,0])
        for weight in [Float(1),0,0,0]{data.f32(weight)}
    }
    return data
}
private func clips()->Data {
    var data=Data();data.u32(0x31504c43);data.u32(4);data.u32(0);data.u32(1)
    for (name,length,end,turn) in [
        ("ped/idle_stance",Float(1),SIMD3<Float>.zero,Float(0)),
        ("authored/sit",1,SIMD3<Float>.zero,0),
        ("authored/hit",0.2,SIMD3<Float>(0.4,0.2,0.3),0.4),
        ("authored/fall",0.6,SIMD3<Float>(0.5,-0.4,-0.8),1.4)] {
        data.string(name);data.f32(length);data.u32(2)
        for bone in [0,1] {
            data.i32(Int32(bone));data.u32(2);data.u32(bone==0 ? 1:0)
            for key in 0...1 {
                data.f32(key==0 ? 0:length)
                let q=simd_quatf(angle:bone==1 && key==1 ? turn:0,axis:SIMD3(1,0,0)).vector
                for value in [q.x,q.y,q.z,q.w]{data.f32(value)}
                if bone==0{data.vector(key==0 && name=="authored/fall" ? SIMD3(0.1,0.2,0.3):key==0 ? .zero:end)}
            }
        }
    }
    return data
}
private func definition()throws->NativeRiderDefinitions.Definition {
    var group:[String:Any]=[:]
    for name in ["open","openRear","getIn","getInRear","pullOut","closeIn","closeInRear","getOut","getOutRear","closeOut","closeOutRear","doorOpenOut","doorCloseIn","doorOpenIn","doorCloseOut"]{group[name]=[]}
    group["getInTime"]=0;group["getOutTime"]=0;group["special"]=0;group["shuffle"]="";group["fallOff"]=["authored:fall",NSNull()]
    let row:[String:Any]=["model":"authored","astride":true,"origin":1.3,"clips":["sit":"authored/sit","hit":"authored/hit"],
        "seats":[["at":[0.3,-0.4,0.8],"side":-1,"rear":false,"opens":false,"turn":0.4]],"group":group]
    return try JSONDecoder().decode(NativeRiderDefinitions.Definition.self,from:JSONSerialization.data(withJSONObject:row))
}
@main private enum Main {
    static func main()throws {
        guard let device=MTLCreateSystemDefaultDevice(),let actor=NativeSkeletalActor(data:skeleton(),vertexCount:2,device:device),
              let compatible=NativeSkeletalActor(data:skeleton(),vertexCount:2,device:device),
              let incompatible=NativeSkeletalActor(data:skeleton(rootOffset:0.3),vertexCount:2,device:device),
              let library=NativeSkeletalAnimationLibrary(data:clips())else{fatalError("Authored production resource decoders unavailable")}
        let definition=try definition(),seat=NativeTrafficOccupants.Seat(id:1,generation:2,model:468,index:0,skin:7,dead:false)
        let frozen=translated(SIMD3(12,24,5))*simd_float4x4(simd_quatf(angle:0.8,axis:SIMD3(0,0,1)))*simd_float4x4(simd_quatf(angle:0.12,axis:SIMD3(1,0,0)))
        for fps in [30,60,120] {
            let cache=TrafficRiderOwnerCache()
            let owner=cache.bind(seat:seat,name:"authored",actor:actor,definition:definition,library:library)
            check(owner.bindCompatible(actor),"Existing rig binding rejected")
            check(!owner.bindCompatible(incompatible) && owner.actor === actor,"Incompatible asset replaced retained palette/capture")
            let dt=1/Double(fps)
            func interval(_ from:Double,_ to:Double)->NativeRiderPoseClock.Interval{.init(start:from,end:to,rejection:nil)}
            _=owner.update(interval:interval(10,10),model:frozen,origin:1.3,input:.init())
            let initial=owner.update(interval:interval(10,10+dt),model:frozen,origin:1.3,input:.init(dead:true))!
            check(owner.falling && !initial.down,"Dead astride rider used living animation")
            var output=initial
            for frame in 2...(fps*3) {
                let now=10+Double(frame)*dt
                if frame==10 {
                    let upgraded=cache.bind(seat:seat,name:"authored",actor:compatible,definition:definition,library:library)
                    check(upgraded === owner && owner.actor === compatible && owner.falling,"Actual renderer cache reset fall after compatible upload")
                }
                output=owner.update(interval:interval(now-dt,now),model:translated(SIMD3(900,800,700)),origin:99,
                    input:.init(dead:frame<5))!
                for c in 0..<4{check(output.model[c]==frozen[c],"Fallen actor followed moving car at \(fps)FPS")}
                check(actor.positions(pose:output.pose).allSatisfy{$0.x.isFinite && $0.y.isFinite && $0.z.isFinite},"Invalid real skinned vertex")
            }
            check(output.down && output.feet != nil,"Fall endpoint not exported")
            // Independent analytic vertex result for the authored root/pelvis.
            let root=translated(SIMD3(0.7,-1,-1.1)),pelvis=translated(SIMD3(0,0,0.5))*simd_float4x4(simd_quatf(angle:1.4,axis:SIMD3(1,0,0)))
            let expected=[frozen*root*SIMD4<Float>(0.1,0.2,0.3,1),frozen*root*pelvis*SIMD4<Float>(0.1,0.2,0.3,1)]
            for (i,point) in actor.positions(pose:output.pose).enumerated() {
                let world=frozen*SIMD4(point,1)
                check(simd_distance(SIMD3(world.x,world.y,world.z),SIMD3(expected[i].x,expected[i].y,expected[i].z))<0.0015,"Actual raw root/bone endpoint differs from authored analytic result")
            }
            let plane=frozen*SIMD4<Float>(0.7,-1,-1.3,1)
            check(simd_distance(output.feet!.position,SIMD3(plane.x,plane.y,plane.z))<0.0015,"Fallen feet used rotated/rest ROOT or projected after model pitch")
            let held=owner.update(interval:.init(start:13,end:900,rejection:887),model:matrix_identity_float4x4,origin:0,input:.init())!
            check(actor.positions(pose:held.pose)==actor.positions(pose:output.pose),"Suspension accumulated fall animation debt")
            let replaced=cache.bind(seat:seat,name:"authored",actor:incompatible,definition:definition,library:library)
            check(replaced !== owner && replaced.actor === incompatible,"Actual cache reused incompatible rig")
            cache.source="different-catalog"
            let changed=cache.bind(seat:seat,name:"authored",actor:incompatible,definition:definition,library:library)
            check(changed !== replaced,"Source replacement retained previous rider task")
        }
        print("PASS \(checks) complete production traffic adapter/raw poser/decoder checks at30/60/120FPS with authored two-vertex rig; Metal buffers only, no GPU draw, network or retail acceptance")
    }
}
