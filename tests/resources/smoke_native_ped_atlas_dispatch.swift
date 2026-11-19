// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
// GPU storage and animation sampling are explicit spies. The executed binding
// decisions, skin parser and per-model resource owner are production source.
struct StorageOptions:OptionSet {let rawValue:Int;static let storageModeShared=StorageOptions(rawValue:1)}
final class MTLBuffer {let bytes:Data;init(_ bytes:Data){self.bytes=bytes}}
final class MTLTexture {let width:Int,height:Int;let identity:String;init(_ w:Int,_ h:Int,_ id:String){width=w;height=h;identity=id}}
final class MTLDevice {
    var fail=false,onMake:(()->Void)?
    func makeBuffer<T>(bytes:[T],length:Int,options:StorageOptions=[])->MTLBuffer? {
        let action=onMake;onMake=nil;action?();if fail{return nil}
        return bytes.withUnsafeBytes{raw in guard length<=raw.count else{return nil};return MTLBuffer(Data(raw.prefix(length)))}
    }
}
enum TextureOption:Hashable {case SRGB,generateMipmaps}
final class TextureLoader {
    var fail=false
    func newTexture(data:Data,options:[TextureOption:Bool])throws->MTLTexture {
        if fail{throw NativePedAtlasLoader.Failure.unavailable}
        check(options[.SRGB]==false && options[.generateMipmaps]==false,"ordinary image upload options")
        let b=Array(data.prefix(24));func n(_ o:Int)->Int{b[o..<o+4].reduce(0){$0*256+Int($1)}}
        return MTLTexture(n(16),n(20),NativePedAtlasLayout.digest(data))
    }
}
final class MTLRenderCommandEncoder {
    var pipeline:Int?,vertexBuffers:[Int:MTLBuffer]=[:],fragmentBuffers:[Int:MTLBuffer]=[:],textures:[Int:MTLTexture]=[:]
    var vertexBytes:Set<Int>=[],fragmentBytes:Set<Int>=[]
    var vertexByteValues:[Int:Data]=[:]
    func setRenderPipelineState(_ v:Int){pipeline=v}
    func setVertexBuffer(_ b:MTLBuffer,offset:Int,index:Int){vertexBuffers[index]=b}
    func setFragmentBuffer(_ b:MTLBuffer,offset:Int,index:Int){fragmentBuffers[index]=b}
    func setVertexBytes<T>(_ b:inout T,length:Int,index:Int){vertexBytes.insert(index);vertexByteValues[index]=withUnsafeBytes(of:&b){Data($0.prefix(length))}}
    func setVertexBytes(_ b:UnsafeRawPointer,length:Int,index:Int){vertexBytes.insert(index);vertexByteValues[index]=Data(bytes:b,count:length)}
    func setFragmentBytes<T>(_ b:inout T,length:Int,index:Int){fragmentBytes.insert(index)}
    func setFragmentTexture(_ v:MTLTexture,index:Int){textures[index]=v}
}
// ACTUAL_SKIN_PARSER
// ACTUAL_HAND_PARSER
// ACTUAL_LOADER_TEST_SUPPORT

final class Frames {
    let a=MTLBuffer(Data([1])),b=MTLBuffer(Data([2]))
    func sample(clip:String,elapsed:Double)->(MTLBuffer,MTLBuffer,Float)?{(a,b,0.5)}
}
final class Owner {
    // ACTUAL_MESH_TYPES
    // ACTUAL_GPU_TYPES
    // ACTUAL_UNIFORMS
    var pedAtlasPipeline:Int?=4,pedAtlasAnimatedPipeline:Int?=5,pedAtlasSkeletalPipeline:Int?=6
    let pipeline=1,animatedPipeline=2,skeletalPipeline:Int?=3
    var pedAtlasFamilies:[String:String]=[:],pedAtlasGPU:[String:PedAtlasGPU]=[:],pedAtlasSource:String?
    var pedAtlasV2Names=Set<String>()
    var pedAtlasLoads:[String:PedAtlasLoad]=[:],pedAtlasAdmission:[String:UUID]=[:],pedAtlasErrors=Set<String>()
    var actorMeshes:[String:Mesh]=[:],skeletalActors:[String:NativeSkeletalActor]=[:],actorAnimations:[String:Frames]=[:]
    var actorParts:[String:[ActorPart]]=[:],actorAttachments:[String:NativeActorAttachment]=[:],actorRetryAfter:[String:Date]=[:]
    var actorLoading=Set<String>()
    let pedAtlasLoader:NativePedAtlasLoader
    var pedModels=["7":"authored"],vehicleModels=["420":"car"],weaponModels=["22":"pistol"],localSkin=7
    var server:ServerAddress?=ServerAddress("http://127.0.0.1:1"),source="one",statuses:[String]=[]
    let device=MTLDevice(),textureLoader=TextureLoader()
    var onStatus:((String)->Void)?
    init(_ peer:Peer){pedAtlasLoader=NativePedAtlasLoader(transfer:peer.make);onStatus={[weak self] in self?.statuses.append($0)}}
    func fixedCJSourceIdentity()->String{source}
    // ACTUAL_OWNER_METHODS
    func genericMayPublish(_ name:String,actorSource:String)->Bool {
        // ACTUAL_GENERIC_GUARD
        return true
    }
    func dispatch(_ name:String,pose:NativeSkeletalActor.Pose?,clip:String="",elapsed:Double=0)->MTLRenderCommandEncoder {
        let encoder=MTLRenderCommandEncoder();var uniforms=Uniforms(viewProjection:matrix_identity_float4x4,settings:SIMD4(1,1,0,128))
        for name in [name] {
            guard let mesh=actorMeshes[name] else{continue}
            // ACTUAL_DRAW_DISPATCH
        }
        return encoder
    }
}
func mainWait(_ label:String,_ condition:()->Bool){let end=Date().addingTimeInterval(10);while !condition(){if Date()>end{fputs("TIMEOUT \(label)\n",stderr);exit(1)};RunLoop.current.run(until:Date().addingTimeInterval(0.002))}}
let root=URL(fileURLWithPath:CommandLine.arguments[1]),catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("fixtures.json"))) as! [[String:Any]]
func entry(_ label:String)->[String:Any]{catalog.first{$0["case"] as?String==label}!}
func path(_ label:String)->String{entry(label)["path"] as!String}
func load(_ owner:Owner,_ peer:Peer,_ label:String="valid") {
    if label.hasSuffix("v2"){owner.bindPedAtlasFamilies(["authored":path("valid")],v2:["authored":path(label)],source:owner.source)}
    else{owner.bindPedAtlasFamilies(["authored":path(label)],source:owner.source)}
    owner.loadPedAtlasActor("authored",family:path(label))
}
func complete(_ owner:Owner,_ peer:Peer,_ success:Bool=true) {
    mainWait("actual owner completion"){peer.drain();return success ? owner.pedAtlasGPU["authored"] != nil:owner.pedAtlasLoads["authored"]==nil}
}
for version in ["valid","validv2"] {
    let peer=Peer(root),owner=Owner(peer);load(owner,peer,version);complete(owner,peer)
    check(owner.actorMeshes.count==1 && owner.skeletalActors.count==1 && owner.pedAtlasGPU.count==1,"complete atomic publication")
    let header=owner.pedAtlasGPU["authored"]!.layout.bytes.withUnsafeBytes{$0.loadUnaligned(as:SIMD4<Float>.self)}
    check(header.w==(version=="validv2" ? 2:1),"draw consumes selected family layout version")
    let actor=owner.skeletalActors["authored"]!
    let pose=NativeSkeletalActor.Pose(palette:[matrix_identity_float4x4],hand:matrix_identity_float4x4,pelvis:matrix_identity_float4x4,
        localTurns:[],localPlaces:[],nativeGlobals:[],rootTurn:simd_quatf(angle:0,axis:SIMD3(0,0,1)),rootHeight:0)
    let staticDraw=owner.dispatch("authored",pose:nil)
    check(staticDraw.pipeline==4 && staticDraw.fragmentBuffers[2] === owner.pedAtlasGPU["authored"]!.layout,"static explicit atlas pipeline/buffer")
    let skinDraw=owner.dispatch("authored",pose:pose)
    check(skinDraw.pipeline==6 && skinDraw.vertexBuffers[2] === actor.skinVertices && skinDraw.vertexBytes.contains(3),"actual skeletal parser/bind remains in vertex namespace")
    check(skinDraw.fragmentBuffers[2] === owner.pedAtlasGPU["authored"]!.layout,"fragment buffer does not overwrite skin")
    var otherMatrix=matrix_identity_float4x4;otherMatrix.columns.3.x=2
    let otherPose=NativeSkeletalActor.Pose(palette:[otherMatrix],hand:matrix_identity_float4x4,pelvis:matrix_identity_float4x4,
        localTurns:[],localPlaces:[],nativeGlobals:[],rootTurn:simd_quatf(angle:0,axis:SIMD3(0,0,1)),rootHeight:0)
    let otherDraw=owner.dispatch("authored",pose:otherPose)
    check(otherDraw.vertexByteValues[3] != skinDraw.vertexByteValues[3] && otherDraw.fragmentBuffers[2] === skinDraw.fragmentBuffers[2],"same-model occurrences aliased pose or failed to share immutable layout")
    owner.actorAnimations["authored"]=Frames()
    let baked=owner.dispatch("authored",pose:nil)
    check(baked.pipeline==5 && baked.vertexBuffers[2] === owner.actorAnimations["authored"]!.a && baked.vertexBytes.contains(4),"baked vertex route preserved")
    owner.actorMeshes["legacy"]=owner.actorMeshes["authored"]
    let legacy=owner.dispatch("legacy",pose:nil)
    check(legacy.pipeline==1 && legacy.fragmentBuffers[2]==nil,"legacy actor does not acquire layout")
    check(!owner.genericMayPublish("authored",actorSource:"one") && owner.genericMayPublish("legacy",actorSource:"one"),"real generic completion guard blocks advertised family only")
    owner.source="two";owner.invalidatePedAtlasSourceIfChanged()
    check(owner.actorMeshes["authored"]==nil && owner.skeletalActors["authored"]==nil && owner.pedAtlasGPU["authored"]==nil,"source change releases complete family")
    check(owner.actorMeshes["legacy"] != nil && owner.pedAtlasFamilies["authored"] != nil,"source invalidation neither clears unrelated actor nor silently downgrades")
}
do {
    let peer=Peer(root),owner=Owner(peer)
    owner.bindPedAtlasFamilies(["authored":path("valid")],v2:["authored":path("valid")],source:"one")
    owner.loadPedAtlasActor("authored",family:path("valid"))
    check(owner.actorMeshes.isEmpty && owner.pedAtlasLoads.isEmpty && peer.all.isEmpty,"v2 advertisement with v1 URL fell back or fetched")
    check(!owner.genericMayPublish("authored",actorSource:"one") && owner.statuses.contains{$0.contains("UNAVAILABLE")},"invalid v2 silently downgraded")
}
for label in ["badskin","badhand","badparts"] {
    let peer=Peer(root),owner=Owner(peer);load(owner,peer,label);complete(owner,peer,false)
    check(owner.actorMeshes.isEmpty && owner.skeletalActors.isEmpty && owner.pedAtlasGPU.isEmpty,"\(label) published a partial model")
    check(owner.statuses.contains{$0.contains("ADMISSION FAILED")},"malformed advertised optional/skin error was hidden")
}
do {
    let peer=Peer(root),owner=Owner(peer);owner.textureLoader.fail=true;load(owner,peer);complete(owner,peer,false)
    check(owner.actorMeshes.isEmpty && owner.pedAtlasGPU.isEmpty,"upload failure published partial mesh")
}
do {
    let peer=Peer(root),owner=Owner(peer);load(owner,peer)
    mainWait("old metadata starts"){!peer.pending.isEmpty};peer.drain()
    mainWait("old member starts"){peer.pending.count>=2}
    let stale=peer.pending
    owner.source="new";owner.invalidatePedAtlasSourceIfChanged();load(owner,peer,"validv2")
    let latest=owner.pedAtlasLoads["authored"]!.token
    for task in stale{peer.reply(task,late:true)}
    RunLoop.current.run(until:Date().addingTimeInterval(0.02))
    check(owner.pedAtlasLoads["authored"]?.token==latest && owner.actorMeshes.isEmpty,"late old result cleared new ownership")
    complete(owner,peer);check(owner.pedAtlasGPU["authored"]?.source=="new","new source failed to admit")
}
do {
    let peer=Peer(root),owner=Owner(peer);var reentered=false
    owner.device.onMake={
        reentered=true;owner.source="away";owner.invalidatePedAtlasSourceIfChanged();owner.source="one"
        load(owner,peer)
    }
    load(owner,peer);complete(owner,peer)
    check(reentered && owner.pedAtlasLoads.isEmpty && owner.pedAtlasGPU.count==1,"reentrant source-away/back broke latest admission")
}
do {
    let peer=Peer(root),owner=Owner(peer);load(owner,peer);complete(owner,peer)
    let first=owner.pedAtlasGPU["authored"]!.family
    owner.bindPedAtlasFamilies(["authored":path("variant")],source:"one")
    check(owner.actorMeshes.isEmpty && owner.pedAtlasGPU.isEmpty,"new family retained previous atlas/layout")
    owner.loadPedAtlasActor("authored",family:path("variant"));complete(owner,peer)
    check(owner.pedAtlasGPU["authored"]!.family != first,"family replacement reused old binding")
    load(owner,peer,"validv2");complete(owner,peer)
    check(owner.pedAtlasGPU["authored"]!.family==path("validv2") && owner.pedAtlasV2Names.contains("authored"),"v2 did not supersede retained v1")
    load(owner,peer);complete(owner,peer)
    check(owner.pedAtlasGPU["authored"]!.family==path("valid") && owner.pedAtlasV2Names.isEmpty,"explicit v2 removal did not re-admit v1")
    owner.bindPedAtlasFamilies([:],source:"one")
    check(owner.actorMeshes.isEmpty && owner.pedAtlasGPU.isEmpty && owner.pedAtlasFamilies.isEmpty,"family removal retained upgraded shader data")
}
print("PASS ped atlas dispatch: \(checks) literal Renderer owner/draw/SKN checks; GPU storage and image decoding explicitly spied")
