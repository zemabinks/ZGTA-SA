#!/usr/bin/env python3
"""Replay the original bA boarding queue and pose transitions on real ANP3/DFF."""
from pathlib import Path
import subprocess,tempfile,json
from smoke_native_foot_animation import SWIFT as FOOT_SWIFT
import prepare_native_animations as archive
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();g.fetch=async url=>{const b=fs.readFileSync(path.join(process.cwd(),'local-only/site',url.split('?')[0]));return{ok:true,json:async()=>JSON.parse(b),arrayBuffer:async()=>{const a=new Bytes(b.length);a.set(b);return a.buffer}}};g.setTimeout=(fn,ms)=>{const t=setTimeout(fn,ms);t.unref();return t};
 const T=load(85339),api=load(49368),pedData=await api.av(),models=JSON.parse(fs.readFileSync('local-only/site/game/native/riders.json')).models,physics=JSON.parse(fs.readFileSync('local-only/site/game/native/vehicles.physics.json')).models;
 const source=fs.readFileSync('local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js','utf8'),start=source.indexOf('function bA(e){'),expression=source.slice(start,source.indexOf('function bP(',start)),order=JSON.parse(fs.readFileSync(process.argv[2])),rows=[],prepared=new Map;
 const clip=async path=>{if(!path)return null;if(!prepared.has(path))prepared.set(path,(async()=>{const[block,name]=path.split(':'),clips=block==='ped'?pedData.clips:await api.nN(block);const clip=api.iA(clips.get(name));if(clip)clip.name=path.replace(':','/');return clip})().catch(()=>null));return prepared.get(path)};
 for(const[id,seat,side]of[[420,0,-1],[420,0,1],[400,2,-1],[403,0,-1],[446,0,-1],[463,0,1],[481,0,-1],[519,0,-1]]){
  const model=models[id],def=physics[id],seats=model.seats.map(s=>({...s,at:new T.Pq0(...s.at),via:s.via?new T.Pq0(...s.via):null,shift:s.shift?new T.Pq0(...s.shift):null})),world=new T.YJl,root=new T.YJl,car=new T.YJl;car.rotation.x=-Math.PI/2;root.position.y=model.origin;root.add(car);world.add(root);root.userData.model=car;
  const bM=new T.PTz,bS=new T.Pq0,gun={weapon:0,hold(){},update(){},dispose(){},muzzle(){return false}},roles=['driver','passenger','fwd','bwd','ahead'],gunClips=Object.fromEntries(roles.map(k=>[k,['','']]));gunClips.low=['',''];
  const deps={d:T,nN:api,F:{Ko:()=>gun},nc:()=>({put(){},dispose(){}}),ah:()=>({model:'bmori',txd:'bmori'}),bm:()=>({group:model.group,astride:model.astrideKind}),bv:()=>seats,by:e=>e.kind==='boat',bh:clip,bf:{wayfarer:'wf'},bg:new Map,bw:new Map,bi:{car:gunClips,astride:gunClips},bs:roles,bM,bS,b_: (clip,time,out)=>clip?.root?.places&&api.XM(clip.root,time,bM,out)?out:out.set(0,0,0),bN:(a,b,x)=>T.cj9.smoothstep(x,a,b),bz:new Set,bl:()=> 'door',bc:new T.Pq0(0,1,0)};
  const debug=expression.replace('return{get state(){return w}', 'return{get debug(){return {time:x,clip:b?.clip?.name,anchor:C.toArray(),transition:O}},get state(){return w}');const make=factory.constructor(...Object.keys(deps),'return ('+debug+')')(...Object.values(deps)),original=make(world),built={id:Number(id),root,kind:def.kind,table:def.table,origin:model.origin,pedalled:!!model.clips.pedal,width:2,bounds:{box:{min:[-1,-2,-1],max:[1,2,1]}}};
  original.setSkin(7);await original.board(built,seat);for(let n=0;n<80;n++)await Promise.resolve();if(!original.ready)throw Error('Original rider not ready '+id);original.enter(side);
  for(let frame=0;frame<900;frame++){
   const method=frame===480?'leave':null;if(method)original.leave(side,null,false);
   root.position.set(Math.sin(frame*.007)*10,model.origin+.1*Math.sin(frame*.011),-frame*.01);root.rotation.set(.08*Math.sin(frame*.013),.2*Math.cos(frame*.009),.03*Math.sin(frame*.017),"YXZ");const delta=[1/60,1/50,1/75][frame%3],input={speed:Math.sin(frame*.009)*20,steer:Math.sin(frame*.019)*.61,lean:Math.sin(frame*.013)*.5,tuck:Math.cos(frame*.017)*.6,pedal:Math.floor(frame/60)%3,crank:frame*.017%1,hop:0};original.update(delta,input);world.updateMatrixWorld(true);
   const row={id,seat,side,frame,delta,input,method,state:original.state,debug:original.debug,door:original.door?{...original.door}:null};
   if(frame%7===0){const figure=original.figure.children[0].children[0].children[0];let mesh;figure.traverse(o=>{if(o.isSkinnedMesh)mesh=o});mesh.skeleton.update();row.vertices=[0,12,57,113,207,330,500,650,800,821].map(index=>{const v=new T.Pq0().fromBufferAttribute(mesh.geometry.attributes.position,order[index]);mesh.applyBoneTransform(order[index],v).applyMatrix4(mesh.matrixWorld);return[index,v.x,-v.z,v.y]});row.matrix=new T.kn4().set(1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1).multiply(car.matrixWorld).toArray()}
   const stood=original.stood(new T.Pq0);if(stood)row.feet={position:[stood.feet.x,-stood.feet.z,stood.feet.y],heading:-stood.heading};rows.push(row);
  }
  original.dispose();
 }
 fs.writeFileSync(process.argv[3],JSON.stringify(rows));
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1]),models=root.appendingPathComponent("local-only/site/game/native/models"),defs=try JSONDecoder().decode(NativeRiderDefinitions.self,from:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/riders.json")))
guard let device=MTLCreateSystemDefaultDevice(),let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:models.appendingPathComponent("animations.clips.bin"))),let actor=NativeSkeletalActor(data:try Data(contentsOf:models.appendingPathComponent("bmori.skel.bin")),vertexCount:822,device:device)else{fatalError("Original local rig unavailable")}
let rows=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))).any as! [[String:Any]]
var playback:NativeRiderPlayback!,label="",previous:NativeSkeletalActor.Pose?,capture:NativeSkeletalActor.Pose?,largest:Float=0,checks=0
func n(_ p:[String:Any],_ k:String)->Double{(p[k] as! NSNumber).doubleValue}
func matrix(_ p:[NSNumber])->simd_float4x4{let v=p.map(\.floatValue);return simd_float4x4(columns:(SIMD4(v[0],v[1],v[2],v[3]),SIMD4(v[4],v[5],v[6],v[7]),SIMD4(v[8],v[9],v[10],v[11]),SIMD4(v[12],v[13],v[14],v[15])))}
for row in rows{
 let id=String(Int(n(row,"id"))),seat=Int(n(row,"seat")),side=Int(n(row,"side")),token="\(id):\(seat):\(side)"
 if token != label{label=token;playback=NativeRiderPlayback(definition:defs.models[id]!,seat:seat,library:library)!;playback.enter(side:side);previous=nil;capture=nil}
 if row["method"] as? String=="leave"{playback.leave(side:side)}
 let p=row["input"] as! [String:Any],input=NativeRiderAnimation.Input(speed:n(p,"speed"),steer:n(p,"steer"),lean:n(p,"lean"),tuck:n(p,"tuck"),pedal:Int(n(p,"pedal")),crank:n(p,"crank"),hop:n(p,"hop")),actual=playback.update(delta:n(row,"delta"),input:input)!
 assert(actual.state.rawValue==row["state"] as! String,"\(token) frame\(row["frame"]!) state \(actual.state) vs \(row["state"]!)")
 if let value=actual.capture{switch value{case .current:capture=previous;case .sample(let seed):capture=actor.riderPose(frame:seed.pose,library:library,figurePosition:SIMD3<Float>(seed.anchor))}}
 let pose=actor.riderPose(frame:actual.sample.pose,library:library,figurePosition:SIMD3<Float>(actual.sample.anchor),figureTurn:Float(actual.turn),previous:actual.transitioning ? capture:nil,transition:actual.transition);previous=pose
 if let expected=row["vertices"] as? [[NSNumber]]{let points=actor.positions(pose:pose),parent=matrix(row["matrix"] as! [NSNumber]);for vertex in expected{let p=parent*SIMD4(points[vertex[0].intValue],1),want=SIMD3(vertex[1].floatValue,vertex[2].floatValue,vertex[3].floatValue),error=simd_distance(SIMD3(p.x,p.y,p.z),want);largest=max(largest,error);assert(error<0.00008,"\(token) frame\(row["frame"]!) vertex\(vertex[0]) \(error)m");checks+=3}}
 if let feet=row["feet"] as? [String:Any],let values=row["matrix"] as? [NSNumber]{let actual=actor.riderFeet(pose:pose,model:matrix(values),origin:Float(defs.models[id]!.origin))!,p=(feet["position"] as! [NSNumber]).map(\.floatValue),error=simd_distance(actual.position,SIMD3(p[0],p[1],p[2]));assert(error<0.00008,"dynamic feet \(token):\(error)");let wanted=Float(n(feet,"heading")),delta=atan2(sin(actual.heading-wanted),cos(actual.heading-wanted));assert(abs(delta)<0.00001,"feet heading");checks+=4}
 if let door=row["door"] as? [String:Any]{assert(actual.doorPart==Int(n(door,"part")));assert(abs(actual.doorOpen-n(door,"open"))<0.0000001)}else{assert(actual.doorPart==nil)}
}
print("PASS: \(rows.count) actual bA boarding/exit/quarter-second transition frames, \(checks) real skinned vertices, maximum \(largest)m")
'''
def main():
 work=Path('/private/tmp/zgta-rider-playback-debug');work.mkdir(exist_ok=True)
 (work/'reference.js').write_text(JS);(work/'order.json').write_text(json.dumps(archive.pedestrian_data(archive.GAME/'bmori.dff')[5]))
 subprocess.run(['node',str(work/'reference.js'),str(work/'order.json'),str(work/'reference.json')],cwd=ROOT,check=True)
 names=['NativeActorAnimation','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeRiderAnimation','NativeBoardingAnimation']
 (work/'verify.swift').write_text((ROOT/'ios/App/NativeSkeletalActor.swift').read_text()+'\n'.join((ROOT/'ios/App'/(name+'.swift')).read_text()for name in names)+(ROOT/'ios/App/NativeRiderPlayback.swift').read_text()+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
 subprocess.run(['swiftc','-Onone','-whole-module-optimization','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),'-o',str(work/'verify')],check=True)
 subprocess.run([str(work/'verify'),str(ROOT),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
