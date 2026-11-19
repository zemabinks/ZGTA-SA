#!/usr/bin/env python3
"""Validate original canopy skinning and jetpack joints using archived models."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
from tests.movement.smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),f=load.factories[49368],g=f.constructor('return globalThis')(),Bytes=f.constructor('return Uint8Array')();
 g.fetch=async url=>{const data=fs.readFileSync(path.join(process.cwd(),'local-only/site',String(url).split('?')[0]));return{ok:true,json:async()=>JSON.parse(data),arrayBuffer:async()=>{const a=new Bytes(data.length);a.set(data);return a.buffer}}};g.setTimeout=(fn,ms)=>{const t=setTimeout(fn,ms);t.unref();return t};
 const T=load(85339),api=load(49368),library=await api.nN('parachute'),data=await api.av(),ped=await api.gp('bmori'),parent=new T.YJl;parent.add(ped.group);let canopy;
 const prepare=clip=>{const p=api.iA(clip);p.name='parachute/'+clip.name.toLowerCase();return p};
 const original=load(54205).ap({ped,prepare,named:name=>api.iA(data.clips.get(name)),sample:api.XM,loadBlock:()=>Promise.resolve(library),build:async()=>canopy=await api.gp('parachute','paracx')});
 const native=JSON.parse(fs.readFileSync('local-only/site/game/native/models/parachute.flight.json')),jetNodes=JSON.parse(fs.readFileSync('local-only/site/game/native/models/jetpack.flight.json')).nodes;
 original.draw(0,{state:1,pitch:0,roll:0},()=>{});for(let i=0;i<120;i++)await Promise.resolve();original.draw(0,{state:11,pitch:0,roll:0},()=>{});for(let i=0;i<120;i++)await Promise.resolve();original.draw(0,null,()=>{});
 const rows=[],convert=new T.kn4().set(1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1),basis=new T.kn4().makeRotationX(-Math.PI/2),states=[1,5,6,7,8,9,10,0,11,12,13,0];
 for(let frame=0;frame<1440;frame++){
  const state=states[Math.floor(frame/60)%states.length],input=state?{state,pitch:Math.sin(frame*.019)*1.2,roll:Math.cos(frame*.023)*.7}:null,delta=[1/60,1/50,1/75][frame%3],heading=Math.sin(frame*.002);
  ped.group.position.set(10+Math.sin(frame*.003),5,-20-frame*.003);ped.group.rotation.y=heading;parent.updateMatrixWorld(true);
  original.draw(delta,input,()=>{});parent.updateMatrixWorld(true);const row={frame,input,delta,heading,position:[ped.group.position.x,-ped.group.position.z,ped.group.position.y]};
  if(canopy.group.visible){let mesh;canopy.figure.traverse(o=>{if(o.isSkinnedMesh)mesh=o});mesh.skeleton.update();row.vertices=[0,11,33,57,91,123,170,211,250].map(index=>{const source=native.order[index],v=new T.Pq0().fromBufferAttribute(mesh.geometry.attributes.position,source);mesh.applyBoneTransform(source,v).applyMatrix4(mesh.matrixWorld);return[index,v.x,-v.z,v.y]});row.parent=convert.clone().multiply(canopy.group.matrixWorld).multiply(basis).toArray()}
  const jet=ped.bones.get(3).children.find(o=>o.getObjectByName('jetball1'));
  if(jet?.visible){jet.updateWorldMatrix(true,true);const inverse=ped.bones.get(3).matrixWorld.clone().invert();row.jet=jetNodes.map(node=>{const object=node.name===jet.name?jet:jet.getObjectByName(node.name);return inverse.clone().multiply(object.matrixWorld).toArray()})}
  rows.push(row);
 }
 fs.writeFileSync(process.argv[2],JSON.stringify(rows));original.dispose();ped.dispose();
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1]),models=root.appendingPathComponent("local-only/site/game/native/models")
guard let device=MTLCreateSystemDefaultDevice(),let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:models.appendingPathComponent("animations.clips.bin"))),let canopy=NativeSkeletalActor(data:try Data(contentsOf:models.appendingPathComponent("parachute.skel.bin")),vertexCount:262,device:device,allowAccessory:true)else{fatalError("Original local canopy rig unavailable")}
let assets=try JSONDecoder().decode(NativeFlightAssets.self,from:Data(contentsOf:models.appendingPathComponent("jetpack.flight.json"))),rows=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))).any as! [[String:Any]],flight=NativeFlightAnimation(duration:library.duration(of:))
var previous:NativeSkeletalActor.Pose?,largest:Float=0,checks=0
func n(_ p:[String:Any],_ k:String)->Double{(p[k] as! NSNumber).doubleValue}
func matrix(_ a:[NSNumber])->simd_float4x4{let v=a.map(\.floatValue);return simd_float4x4(columns:(SIMD4(v[0],v[1],v[2],v[3]),SIMD4(v[4],v[5],v[6],v[7]),SIMD4(v[8],v[9],v[10],v[11]),SIMD4(v[12],v[13],v[14],v[15])))}
for state in [1,11,0]{_ = flight.update(delta:0,input:state==0 ? nil:.init(state:state),position:.zero,heading:0)}
for row in rows {
 let input=(row["input"] as? [String:Any]).map{NativeFlightAnimation.Input(state:Int(n($0,"state")),pitch:n($0,"pitch"),roll:n($0,"roll"))},p=(row["position"] as! [NSNumber]).map(\.doubleValue),actual=flight.update(delta:n(row,"delta"),input:input,position:SIMD3(p[0],p[1],p[2]),heading:-n(row,"heading"))
 if let frame=actual.canopy {let pose=canopy.canopyPose(clip:frame.clip,time:frame.time,easing:frame.easing,pitch:frame.pitch,roll:frame.roll,library:library,previous:previous);previous=pose;if frame.visible {let points=canopy.positions(pose:pose),parent=matrix(row["parent"] as! [NSNumber]);for vertex in row["vertices"] as! [[NSNumber]]{let transformed=parent*SIMD4(points[vertex[0].intValue],1),expected=SIMD3(vertex[1].floatValue,vertex[2].floatValue,vertex[3].floatValue),error=simd_distance(SIMD3(transformed.x,transformed.y,transformed.z),expected);largest=max(largest,error);assert(error<0.00008,"frame \(row["frame"]!) canopy vertex \(vertex[0]): \(error)m");checks+=3}}}
 if let frame=actual.jet {let matrices=assets.jetPose(frame),expected=row["jet"] as! [[NSNumber]];assert(matrices.count==expected.count);for index in matrices.indices{let want=matrix(expected[index]);for col in 0..<4{for axis in 0..<4{let error=abs(matrices[index][col][axis]-want[col][axis]);largest=max(largest,error);assert(error<0.000003,"jet joint \(index) \(error)");checks+=1}}}}
}
print("PASS: \(rows.count) actual original flight frames, \(checks) canopy skin/jet node comparisons; maxerror \(largest)")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-flight-assets-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'reference.json')],cwd=ROOT,check=True)
  names=['NativeActorAnimation','NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFlightAssets','NativeFootAnimation','NativeRiderAnimation']
  (work/'verify.swift').write_text('\n'.join((ROOT/'ios/App'/(name+'.swift')).read_text()for name in names)+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(ROOT),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
