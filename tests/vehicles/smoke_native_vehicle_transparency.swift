// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
private var checks=0
private func check(_ value:Bool,_ name:String){checks+=1;precondition(value,name)}
private func document(_ draws:[[String:Any]])throws->Data {
 let node:[String:Any]=["name":"authored-shell","parent":-1,"position":[0,0,0],"rotation":[0,0,0,1],"scale":[1,1,1],"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"matrixAutoUpdate":true,"visible":true,"wheel":false,"damaged":false,"lowDetail":false]
 return try JSONSerialization.data(withJSONObject:["version":1,"id":999,"kind":"car","nodes":[node],"draws":draws,"joints":["damage":[],"wheels":[],"rotors":[],"gear":[],"nozzles":[],"rearSteerOnly":false]])
}
private func row(_ start:Int,opacity:Double?=nil,glass:Bool?=nil,alphaTest:Double=0)->[String:Any] {
 var r:[String:Any]=["node":0,"start":start,"count":6,"materialVisible":true,"lens":-1,"texture":0,"litTexture":0,"alphaTest":alphaTest]
 if let opacity{r["opacity"]=opacity};if let glass{r["glass"]=glass};return r
}
// ACTUAL_UNIFORMS
private enum MTLPrimitiveType {case triangle}
private enum MTLIndexType {case uint32}
private final class EncoderSpy {
 var pipeline=0,depth=0,vertices=0,atlas=0
 var material=SIMD4<Float>.zero,paint=SIMD4<Float>.zero,uniforms:Uniforms?
 var events:[[Int]]=[],alphas:[Float]=[],paints:[SIMD4<Float>]=[]
 func setDepthStencilState(_ value:Int){depth=value}
 func setRenderPipelineState(_ value:Int){pipeline=value}
 func setVertexBuffer(_ value:Int,offset:Int,index:Int){check(index==0 && offset==0,"Mesh binding");vertices=value}
 func setFragmentTexture(_ value:Int,index:Int){check(index==0,"Atlas binding");atlas=value}
 func setVertexBytes<T>(_ value:inout T,length:Int,index:Int){}
 func setFragmentBytes<T>(_ value:inout T,length:Int,index:Int){
  if index==1{uniforms=withUnsafeBytes(of:&value){$0.loadUnaligned(as:Uniforms.self)}}
  if index==2{material=withUnsafeBytes(of:&value){$0.loadUnaligned(as:SIMD4<Float>.self)}}
  if index==3{paint=withUnsafeBytes(of:&value){$0.loadUnaligned(as:SIMD4<Float>.self)}}
 }
 func drawIndexedPrimitives(type:MTLPrimitiveType,indexCount:Int,indexType:MTLIndexType,indexBuffer:Int,indexBufferOffset:Int){events.append([vertices,atlas,pipeline,depth,indexBuffer,indexBufferOffset,indexCount]);alphas.append(uniforms!.tintColor.w);paints.append(paint)}
}
private typealias MTLRenderCommandEncoder=EncoderSpy
private final class RendererCarrier {
 struct Mesh {let vertices:Int,indices:Int,indexCount:Int,atlas:Int}
 struct TransparentVehicleDraw {let mesh:Mesh,part:NativeVehicleRig.Draw,uniforms:Uniforms,pipeline:Int;let painted:Bool,depth:Float;var bindTextures:((MTLRenderCommandEncoder)->Bool)?=nil}
 let depth=9,pipeline=99
 // ACTUAL_ENCODER
 func test(){
  let e=EncoderSpy();var packets:[TransparentVehicleDraw]=[]
  for (i,z)in [Float(0.2),0.8,0.8].enumerated(){
   let part=NativeVehicleRig.Draw(start:i*6,count:6,node:0,transform:matrix_identity_float4x4,layerOverride:-1,emissive:false,scorched:false,alphaTest:0,paint:SIMD4(Float(i),0,0,1),transparent:true)
   let u=Uniforms(viewProjection:matrix_identity_float4x4,settings:SIMD4(128,128,0,128))
   packets.append(.init(mesh:.init(vertices:100+i,indices:200+i,indexCount:6,atlas:300+i),part:part,uniforms:u,pipeline:400+i,painted:true,depth:z))
  }
  encodeTransparentVehicles(packets,encoder:e)
  check(e.events.map{$0[0]}==[101,102,100],"Actual renderer stable far-to-near ordering")
  for (at,i)in [1,2,0].enumerated(){check(e.events[at]==[100+i,300+i,400+i,9,200+i,i*24,6],"Independent mesh/atlas/pipeline/index/offset state survives deferred ordering");check(e.paints[at].x==Float(i),"Per-instance paint survives sorting")}
  check(e.alphas==[1,1,1],"Source opacity not multiplied into instance alpha again")
  check(e.pipeline==99 && e.depth==9,"Encoder restores normal world pipeline/depth")
  packets[1].bindTextures={_ in false}
  packets[0].bindTextures={encoder in encoder.setFragmentTexture(777,index:0);return true}
  let native=EncoderSpy();encodeTransparentVehicles(packets,encoder:native)
  check(native.events.map{$0[0]}==[102,100],"Failed native image binding cannot draw a stale atlas")
  check(native.events.map{$0[1]}==[302,777],"Sorted native image closure retains its instance; legacy atlas remains independent")
  check(native.pipeline==99 && native.depth==9,"Mixed native/legacy transparency restores the production states")
 }
}
@main private enum Test {
 static func main()throws {
  let r=NativeVehicleRig(data:try document([row(0),row(6,opacity:0.5),row(12,opacity:0.4),row(18,opacity:1),row(24,alphaTest:0.35),row(30,glass:true)]))!
  var state=NativeVehicleRig.State();let frame=r.pose(.init(),state:&state,delta:0)
  check(frame.draws.map(\.start)==[0,6,18,24,30] && frame.draws.map(\.count)==[6,12,6,6,6],"Only compatible transparency groups merge")
  check(frame.draws.map(\.transparent)==[false,true,false,true,true],"Opacity, texture cutout and explicit glass classes")
  check(frame.opaque.draws.map(\.start)==[0,18] && frame.transparent.map(\.start)==[6,24,30],"Actual frame phase split excludes late alpha from opaque phase")
  let old=NativeVehicleRig(data:try document([row(0)]))!;var oldState=NativeVehicleRig.State()
  check(!old.pose(.init(),state:&oldState,delta:0).draws[0].transparent,"Old metadata defaults remain opaque")
  for opacity in [-0.01,1.01]{check(NativeVehicleRig(data:try document([row(0,opacity:opacity)]))==nil,"Invalid new opacity rejected")}
  let points=[SIMD3<Float>(-2,-4,0.2),SIMD3<Float>(4,8,0.8)]
  r.installSortCenters(positions:points,indices:(0..<36).map{UInt32($0%2)})
  let centered=r.pose(.init(),state:&state,delta:0)
  check(centered.draws.allSatisfy{$0.sortCenter==SIMD3(1,2,0.5)},"Original mesh/node groups share their indexed bounds centre")
  check(NativeVehicleRig.projectedDepth(SIMD3(0,0,0.8),matrix:matrix_identity_float4x4)==0.8,"Orthographic/projected depth")
  var project=matrix_identity_float4x4;project.columns.3.w=2
  check(NativeVehicleRig.projectedDepth(SIMD3(0,0,0.8),matrix:project)==0.4,"Perspective divide used for sorting")
  project.columns.3.w=0
  check(NativeVehicleRig.projectedDepth(.zero,matrix:project)==(-Float.infinity),"Zero-w centre remains deterministic")
  check(NativeVehicleRig.farToNear([0.5,0.8,0.5,-.infinity,.nan,.infinity])==[1,0,2,3,4,5],"Stable ties and invalid-depth fallback")
  check(NativeVehicleRig.farToNear(Array(repeating:0.4,count:32))==Array(0..<32),"Distinct identical-depth instances retain insertion identity")
  RendererCarrier().test()
  print("VEHICLE_TRANSPARENCY_PASS \(checks) authored actual Rig/renderer checks")
 }
}
