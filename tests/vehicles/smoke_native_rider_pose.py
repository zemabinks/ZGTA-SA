#!/usr/bin/env python3
"""Compare the distinct original bA rider sampler/root/seat hierarchy to Swift."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import json,subprocess,tempfile
import tools.assets.prepare_native_animations as archive
from tests.movement.smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],global=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 global.fetch=async url=>{const bytes=fs.readFileSync(path.join(process.cwd(),'local-only/site',url.split('?')[0]));return{ok:true,json:async()=>JSON.parse(bytes),arrayBuffer:async()=>{const value=new Bytes(bytes.length);value.set(bytes);return value.buffer}}};
 global.setTimeout=(callback,delay)=>{const timer=setTimeout(callback,delay);timer.unref();return timer};global.clearTimeout=clearTimeout;
 const T=load(85339),api=load(49368),data=await api.av(),geometry=load(88711),catalogue=load(72197),modelParser=load(78315).A,source=fs.readFileSync('local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js','utf8');
 const poseStart=source.indexOf('i=function(e){let t=e.bones.get(nN.LS.ROOT)'),poseEnd=source.indexOf('}(o),o.group.rotation.x=',poseStart);
 if(poseStart<0||poseEnd<0)throw Error('Original raw rider poser not found');
 const poseFactory=factory.constructor('nN','bM','bS','return('+source.slice(poseStart+2,poseEnd+1)+')')(api,new T.PTz,new T.Pq0);
 const table=JSON.parse(fs.readFileSync('local-only/site/game/native/seating.json')).models,order=JSON.parse(fs.readFileSync(process.argv[2])),cases=[];
 async function clip(name){if(!name)return null;const[block,key]=name.split('/'),clips=block==='ped'?data.clips:await api.nN(block);return api.iA(clips.get(key))}
 for(const id of [420,411,403,446,571,468,448,463,481,509,510,519,537]){
  const def=catalogue.Wd.find(x=>x.id===id),options=catalogue.AX({id}),assets=catalogue.yc(options),parsed=modelParser(fs.readFileSync('local-only/site/game/'+def.model+'.dff'));
  const root=geometry.yK(parsed,new Map(),{kind:'vehicle',damage:true,blades:true,lowDetail:true,wheels:load(90317).y(id)});geometry.u2(root,[],new Map(),{colors:assets.colors,wheelScale:assets.wheelScale});
  const box=new T.NRn().setFromObject(root);root.position.y=-box.min.y;
  const body=new T.YJl;body.rotation.set(.12,.48,-.15,'YXZ');body.position.set(10,5,-20);body.add(root);
  const model=root.userData.model,seat=new T.Pq0().setFromMatrixPosition(root.userData.frames.get('ped_frontseat'));
  if(!table[id].astride && def.type!=='boat' && Math.abs(seat.x)>=.15)seat.x=-Math.abs(seat.x);
  const ped=await api.gp('bmori','bmori'),poser=poseFactory(ped);ped.group.rotation.x=Math.PI/2;model.add(ped.group);ped.figure.position.copy(seat);
  model.updateWorldMatrix(true,true);
  const convert=new T.kn4().set(1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1),nativeMatrix=convert.multiply(model.matrixWorld).toArray();
  const config=table[id],base=config.clips.sit;
  for(let frame=0;frame<25;frame++){
   const left=frame%2===0,steer=config.clips[left?'left':'right'],tuck=config.clips[frame%3===0?'forward':'backward'],mixes=[];
   poser.set(await clip(base),0);
   for(const [name,weight]of [[steer,frame/24],[tuck,frame/48]])if(name){const prepared=await clip(name);if(prepared){poser.mix(prepared,prepared.duration,weight);mixes.push({clip:name,time:prepared.duration,weight})}}
   body.updateMatrixWorld(true);let mesh;ped.figure.traverse(x=>{if(x.isSkinnedMesh)mesh=x});mesh.skeleton.update();
   const indices=[0,12,57,113,207,330,500,650,800,821],vertices=indices.map(index=>{const v=new T.Pq0().fromBufferAttribute(mesh.geometry.attributes.position,order[index]);mesh.applyBoneTransform(order[index],v).applyMatrix4(mesh.matrixWorld);return[index,v.x,-v.z,v.y]});
   cases.push({id,frame,base,time:0,mixes,seat:seat.toArray(),matrix:nativeMatrix,vertices});
  }
  ped.dispose();
 }
 fs.writeFileSync(process.argv[3],JSON.stringify(cases));
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1]),models=root.appendingPathComponent("local-only/site/game/native/models")
guard let device=MTLCreateSystemDefaultDevice(),let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:models.appendingPathComponent("animations.clips.bin"))),let actor=NativeSkeletalActor(data:try Data(contentsOf:models.appendingPathComponent("bmori.skel.bin")),vertexCount:822,device:device)else{fatalError("Local Metal rig unavailable")}
let rows=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))).any as! [[String:Any]]
var largest:Float=0,comparisons=0
for row in rows{
 let mixes=(row["mixes"] as! [[String:Any]]).map{NativeRiderAnimation.Sample(clip:$0["clip"] as! String,time:($0["time"] as! NSNumber).doubleValue,weight:($0["weight"] as! NSNumber).doubleValue)}
 let frame=NativeRiderAnimation.Frame(base:row["base"] as? String,time:(row["time"] as! NSNumber).doubleValue,mixes:mixes),seat=(row["seat"] as! [NSNumber]).map(\.floatValue),values=(row["matrix"] as! [NSNumber]).map(\.floatValue)
 let matrix=simd_float4x4(columns:(SIMD4(values[0],values[1],values[2],values[3]),SIMD4(values[4],values[5],values[6],values[7]),SIMD4(values[8],values[9],values[10],values[11]),SIMD4(values[12],values[13],values[14],values[15])))
 let pose=actor.riderPose(frame:frame,library:library,figurePosition:SIMD3(seat[0],seat[1],seat[2])),points=actor.positions(pose:pose)
 for vertex in row["vertices"] as! [[NSNumber]]{
  let actual=matrix*SIMD4(points[vertex[0].intValue],1),expected=SIMD3(vertex[1].floatValue,vertex[2].floatValue,vertex[3].floatValue),error=simd_distance(SIMD3(actual.x,actual.y,actual.z),expected);largest=max(largest,error)
  assert(error<0.00003,"vehicle \(row["id"]!) frame \(row["frame"]!) raw rider vertex \(vertex[0]): \(error)m");comparisons+=3
 }
}
print("PASS: \(rows.count) original raw rider poses, \(comparisons) world vertex comparisons across13 real vehicle seat/model hierarchies; maximum \(largest)m")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-rider-pose-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS);(work/'order.json').write_text(json.dumps(archive.pedestrian_data(archive.GAME/'bmori.dff')[5]))
  subprocess.run(['node',str(work/'reference.js'),str(work/'order.json'),str(work/'reference.json')],cwd=ROOT,check=True)
  rider=ROOT/'ios/App/NativeRiderAnimation.swift'
  actor=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text()
  combined=(ROOT/'ios/App/NativeActorAnimation.swift').read_text()+actor+(ROOT/'ios/App/NativeGunAnimation.swift').read_text()+(ROOT/'ios/App/NativeSwimAnimation.swift').read_text()+(ROOT/'ios/App/NativeFlightAnimation.swift').read_text()+(ROOT/'ios/App/NativeFootAnimation.swift').read_text()+rider.read_text()+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT
  (work/'verify.swift').write_text(combined)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(ROOT),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
