// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
private var checks=0
private func require(_ value:@autoclosure()->Bool,_ message:String){checks+=1;if !value(){fatalError(message)}}
private enum Expected:Error {case reject}
private struct OwnerCase:Decodable {let id:Int32,name:String,skeleton:String}

@main struct Main {
 @MainActor static func main()async throws {
    let out=URL(fileURLWithPath:CommandLine.arguments[1]),base=out.appendingPathComponent("files",isDirectory:true)
    guard let device=MTLCreateSystemDefaultDevice()else{require(!CommandLine.arguments.contains("--require-gpu"),"Required Metal unavailable");print("SKIP actual Metal unavailable");return}
    let catalog=try NativeSAMPStockModels.decode(Data(contentsOf:out.appendingPathComponent("manifest.json")))
    let files=try NativeSAMPStockAssetLoader(assetBaseURL:base,allowLocalFiles:true)
    let loader=try NativeStockPedLoader(fileLoader:files,sourceIdentity:{"rig-probe"})
    func load(_ id:Int32)async throws->NativeStockPedLoader.Prepared {
        let resolution=try catalog.resolve(id:id,assetBaseURL:base)
        return try await withCheckedThrowingContinuation{continuation in loader.load(resolution){continuation.resume(with:$0)}}
    }
    let value=try await load(19999),plan=value.plan,data=plan.skeleton.encodedSKN1(),count=plan.skeleton.vertices.count
    func actor(_ data:Data)->NativeSkeletalActor {
        let actor=NativeSkeletalActor(data:data,vertexCount:count,device:device);require(actor != nil,"Authored compatibility control is not a valid native rig");return actor!
    }
    func changed(_ offset:Int,_ number:UInt32)->Data {
        var result=data;result.replaceSubrange(offset..<offset+4,with:[UInt8(truncatingIfNeeded:number),UInt8(truncatingIfNeeded:number>>8),UInt8(truncatingIfNeeded:number>>16),UInt8(truncatingIfNeeded:number>>24)]);return result
    }
    func changedFloat(_ offset:Int,_ number:Float)->Data{changed(offset,number.bitPattern)}
    func number(_ offset:Int)->Float{let b=[UInt8](data);return Float(bitPattern:UInt32(b[offset])|UInt32(b[offset+1])<<8|UInt32(b[offset+2])<<16|UInt32(b[offset+3])<<24)}
    let original=actor(data),copy=actor(data)
    require(original.matchesRig(copy) && copy.matchesRig(original),"Identical rigs rejected")
    require(!original.matchesRig(copy,tolerance:-1) && !original.matchesRig(copy,tolerance:.nan) && !original.matchesRig(copy,tolerance:1),"Invalid rig tolerance accepted")
    let frames=plan.skeleton.frames.count,bones=plan.skeleton.bones.count,boneStart=144+frames*72,vertexStart=boneStart+bones*68
    let translation=144+72+8+48
    let tiny=actor(changedFloat(translation,number(translation)+0.00005))
    require(original.matchesRig(tiny) && !original.matchesRig(tiny,tolerance:0),"Documented numerical tolerance ignored")
    var controls:[(String,Data)]=[
        ("correction",changedFloat(16+48,number(16+48)+0.01)),
        ("axis",changedFloat(80,number(80)+0.01)),
        ("frame-rest",changedFloat(translation,number(translation)+0.01)),
        ("inverse-bind",changedFloat(boneStart+4+48,number(boneStart+4+48)+0.01)),
        ("vertex-point",changedFloat(vertexStart,number(vertexStart)+0.01))]
    require(frames>=3 && bones>=2,"Authored multi-frame/palette controls missing")
    controls.append(("parent",changed(144+2*72,plan.skeleton.frames[2].parent==0 ? 1:0)))
    controls.append(("palette-frame",changed(boneStart,UInt32((plan.skeleton.bones[0].frame+1)%frames))))
    var weights=changedFloat(vertexStart+16,0.9);weights.replaceSubrange(vertexStart+20..<vertexStart+24,with:[UInt8(truncatingIfNeeded:Float(0.1).bitPattern),UInt8(truncatingIfNeeded:Float(0.1).bitPattern>>8),UInt8(truncatingIfNeeded:Float(0.1).bitPattern>>16),UInt8(truncatingIfNeeded:Float(0.1).bitPattern>>24)])
    controls.append(("weights",weights))
    var indices=data;indices[vertexStart+12]=UInt8((Int(indices[vertexStart+12])+1)%bones);controls.append(("vertex-palette",indices))
    for (label,bytes)in controls {
        let other=actor(bytes)
        require(other.vertexCount==original.vertexCount,"Equal-count control changed topology size")
        require(!original.matchesRig(other) && !other.matchesRig(original),"Foreign equal-count rig admitted: \(label)")
    }
    let reserve=try NativeStockPedAllocation.reservation(value,device:device)
    var validations=0,rejected=false
    do{_=try NativeStockPedAllocation.upload(value,device:device,allowance:reserve,validateActor:{candidate in
        validations+=1;require(candidate.matchesRig(original),"Validation receives another rig");throw Expected.reject
    })}catch Expected.reject{rejected=true}
    require(rejected && validations==1,"Validation rejection did not stop real material construction")
    let uploaded=try NativeStockPedAllocation.upload(value,device:device,allowance:reserve,validateActor:{candidate in validations+=1;require(candidate.matchesRig(original),"Valid actual uploader changed rig")})
    require(uploaded.resource.actor.matchesRig(original) && validations==2,"Actual uploader bypassed rig validation")
    let ownerCases=try JSONDecoder().decode([OwnerCase].self,from:Data(contentsOf:out.appendingPathComponent("owner-cases.json")))
    for owner in ownerCases {
        let prepared=try await load(owner.id),bytes=try Data(contentsOf:URL(fileURLWithPath:owner.skeleton))
        guard let expected=NativeSkeletalActor(data:bytes,vertexCount:prepared.plan.skeleton.vertices.count,device:device)else{throw Expected.reject}
        var checked=false
        let allocation=try NativeStockPedAllocation.reservation(prepared,device:device)
        let resource=try NativeStockPedAllocation.upload(prepared,device:device,allowance:allocation,validateActor:{candidate in
            checked=true;require(candidate.matchesRig(expected) && expected.matchesRig(candidate),"Original raw/prepared rig differs: \(owner.name)")
        })
        require(checked && resource.resource.actor.vertexCount==expected.vertexCount,"Original family bypassed actual rig admission")
    }
    print("PASS \(checks) actual rig/skin/constructor checks, \(controls.count) equal-count negative controls, \(ownerCases.count) original pairs; no renderer/retail claim")
 }
}
