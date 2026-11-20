#!/usr/bin/env python3
"""Replay actual nC remote control clauses + real R6/DFF against Swift."""

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
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'tests/vehicles/smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],global=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 global.fetch=async url=>{const bytes=fs.readFileSync(path.join(process.cwd(),'local-only/site',url.split('?')[0]));return{ok:true,json:async()=>JSON.parse(bytes),arrayBuffer:async()=>{const value=new Bytes(bytes.length);value.set(bytes);return value.buffer}}};global.setTimeout=(fn,dt)=>{const t=setTimeout(fn,dt);t.unref();return t};global.clearTimeout=clearTimeout;
 const T=load(85339),api=load(49368),weapons=load(60662),data=await api.av(),style=await load(66799).r({model:'bmori'},data),source=fs.readFileSync('local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js','utf8'),order=JSON.parse(fs.readFileSync(process.argv[2]));
 const re={JUMP:20,HANG:21,PULL:22,EDGE:23,STAND:24,VAULT:25},ri={NONE:0,...re,ROLL_L:26,ROLL_R:27,BLOCK:28,KILL:29,KILLED:30,STANCE:36},rv={USE:32,USE2:33,DRINK:34,EAT:35};
 const between=(a,b)=>{const start=source.indexOf(a),end=source.indexOf(b,start);if(start<0||end<0)throw Error('Original remote clause unavailable:'+a);return source.slice(start,end)};
 const rs=factory.constructor('re','return '+between('rs={','},rc=').slice(3)+'}')(re);
 const rp=factory.constructor('nN','let ru=null;return('+between('async function rp(','var rh=')+')')(api);
 const rd=factory.constructor('ri','rs','re','rp','return('+between('function rd(','async function rp(')+')')(ri,rs,re,rp);
 const nZ=factory.constructor('return('+between('function nZ(','var n0=')+')')();
 const rN=factory.constructor('rk','rv','rz','rS','rj','return('+between('function rN(','let rz=')+')')({32:'vend_use',33:'vend_use_pt2',34:'vend_drink_p',35:'vend_eat_p'},rv,new WeakMap,()=>api.nN('vending'),[]);
 const health=between('let D=e.person.life;','let H=N.life>0');
 const begin=source.indexOf('let V=null!==N.aim&&0!==N.weapon,K=null'),update=source.indexOf('if(C.update(l,{ratio:Math.min(2,N.move)',begin),end=source.indexOf('),N.riding',update),prefix=source.slice(begin,update),call=source.slice(update+3,end+1);
 const control=factory.constructor('d','F','nN','ri','ng','tk',`const jR=1.3;return(e,t,l,C,N,A)=>{${prefix};const forward=${call};const shot=C.shot&&$;if(shot)e.person.fired++;return{travel:[C.side,forward],shot,shotLeft:C.shotLeft,firing:C.firing,dead:C.dead,busy:C.busy,tagged:C.tagged??null,fired:e.person.fired}}`)(T,weapons,api,ri,null,new Map);
 const react=factory.constructor('nN','F','an','ri','tN','ay','aw',`return(e,t,C,N,A)=>{${health}}`)(api,weapons,['koSkidBack','koSpinR','koSkidFront','koSpinL','floorHit','floorHitF'],ri,true,()=> 'koFront',()=>0);
 const cases=[],scenarios=['move','shots','air','actions','swim'];
 for(const scenario of scenarios){
  const ped=await api.gp('bmori','bmori'),C=api.R6(ped,style,data.clips),e={person:{fired:null,flight:null,ground:null,life:null,hitUntil:-Infinity,down:0,fall:null},steps:[],group:{position:new T.Pq0}},count=scenario==='actions'?1700:scenario==='swim'?1000:700;
  C.update(0,{swim:{state:1}});for(let i=0;i<30;i++)await Promise.resolve();
  let armed=-1,previousAction=0,previousScript=null;
  for(let frame=0;frame<count;frame++){
   const delta=[1/60,1/50,1/75][frame%3],now=frame*17+1000;
   let movement=frame<550?(Math.sin(frame*.023)+1)*1.6:0,weapon=scenario==='shots'?[22,25,16,0][Math.floor(frame/170)%4]:0,aim=scenario==='shots'&&frame%140<120?Math.sin(frame*.019)*.7:null,shots=scenario==='shots'?Math.floor(frame/7):0,airborne=scenario==='air'&&frame%300>=30&&frame%300<220;
   let action=scenario==='actions'?[0,20,21,22,23,24,0,25,0,26,27,28,36,31,32,33,34,35,29,30,0][Math.floor(frame/70)%21]:0;
   if(scenario==='swim')action=[10,11,12,13,15,14,15,14,10,16,0][Math.floor(frame/80)%11];
   const life=scenario==='actions'&&frame>=1400&&frame<1500?0:scenario==='move'?100-Math.floor(frame/130)*5:100,armour=scenario==='move'?Math.max(0,20-Math.floor(frame/70)*5):0;
   const velocity=[Math.sin(frame*.017)*5,Math.cos(frame*.017)*5,airborne?(frame%300<75?6:-12):0],position=[0,0,airborne?8:0],heading=Math.sin(frame*.015)*2;
   const script=scenario==='actions'&&frame>=1520?frame<1580?'ped/handsup/h/1':frame<1650?'ped/phone_in/o/2':null:null;
   const input={position,heading,velocity,movement,airborne,crouching:scenario==='shots'&&frame%200>=100&&frame%200<165,weapon,aim,action,shots,latestShots:shots,life,armour,down:scenario==='actions'&&frame>=1000&&frame<1050?3:0,paused:false,riding:false,pitch:Math.sin(frame*.013),script,nearFlooredTarget:false};
   const N={position:new T.Pq0(position[0],position[2],-position[1]),heading:-heading,velocity:new T.Pq0(velocity[0],velocity[2],-velocity[1]),move:movement,air:airborne,crouch:input.crouching,weapon,aim,act:action,fired:shots,life,armour,down:input.down,riding:null,swim:load(19863).M9(action,movement,input.pitch),fly:null};
   const A=(action>=20&&action<=35||action===36)?action:0;
   if(A!==previousAction){const pending=rd(C,previousAction,A);nZ(C,previousAction,A);rN(C,previousAction,A);const resolved=await pending;if(A===30&&resolved)e.person.fall=resolved.die;previousAction=A;for(let i=0;i<20;i++)await Promise.resolve()}
   if(weapon!==armed){C.arm(await weapons.OP(weapon));armed=weapon}
   react(e,now,C,N,A);for(let i=0;i<8;i++)await Promise.resolve();
   if(script!==previousScript){const old=previousScript;previousScript=script;if(old&&C.tagged===old)C.rest();if(script){const[block,name,how]=script.split('/');const clip=block==='ped'?name:(await api.nN(block)).get(name);C.act(clip,how==='l',{once:how==='o',tag:script})}}
   if(!N.air)e.person.ground=N.position.y;e.group.position.copy(N.position);e.steps=[{fired:shots}];
   const expected=control(e,now,delta,C,N,A),item={scenario,frame,delta,now,input,expected};
   if(frame%15===0){ped.group.updateMatrixWorld(true);let mesh;ped.figure.traverse(x=>{if(x.isSkinnedMesh)mesh=x});mesh.skeleton.update();expected.vertices=[0,57,207,330,500,800].map(index=>{const v=new T.Pq0().fromBufferAttribute(mesh.geometry.attributes.position,order[index]);mesh.applyBoneTransform(order[index],v).applyMatrix4(mesh.matrixWorld);return[index,v.x,-v.z,v.y]})}
   cases.push(item);
  }
  ped.dispose();
 }
 fs.writeFileSync(process.argv[3],JSON.stringify(cases));
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game"),models=game.appendingPathComponent("native/models")
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:models.appendingPathComponent("animations.clips.bin")))!,definitions=try NativeFootAnimationDefinitions(data:Data(contentsOf:game.appendingPathComponent("world/peds.json"))),weapons=try NativeFootWeaponAnimation.load(data:Data(contentsOf:game.appendingPathComponent("native/foot-animation.json")))
guard let device=MTLCreateSystemDefaultDevice(),let actor=NativeSkeletalActor(data:try Data(contentsOf:models.appendingPathComponent("bmori.skel.bin")),vertexCount:822,device:device)else{fatalError("Native local rig unavailable")}
let cases=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))).any as! [[String:Any]]
var scenario="",remote:NativeRemoteFootAnimation!,checks=0,largest:Float=0
for row in cases{
 let label=row["scenario"] as! String,frame=row["frame"] as! Int,p=row["input"] as! [String:Any],e=row["expected"] as! [String:Any]
 if label != scenario{scenario=label;remote=NativeRemoteFootAnimation(library:library,style:definitions.style(model:"bmori",library:library),weapons:weapons,random:{0.37})}
 func n(_ key:String)->Double{(p[key] as! NSNumber).doubleValue};func b(_ key:String)->Bool{p[key] as! Bool};func v(_ key:String)->SIMD3<Double>{let a=(p[key] as! [NSNumber]).map(\.doubleValue);return SIMD3(a[0],a[1],a[2])}
 let snapshot=NativeRemoteFootAnimation.Snapshot(position:v("position"),heading:n("heading"),velocity:v("velocity"),movement:n("movement"),airborne:b("airborne"),crouching:b("crouching"),weapon:Int(n("weapon")),aim:(p["aim"] as? NSNumber)?.doubleValue,action:Int(n("action")),shots:Int(n("shots")),latestShots:Int(n("latestShots")),life:n("life"),armour:n("armour"),down:Int(n("down")),paused:b("paused"),riding:b("riding"),pitch:n("pitch"),script:p["script"] as? String,nearFlooredTarget:b("nearFlooredTarget"))
 let output=remote.update(delta:(row["delta"] as! NSNumber).doubleValue,nowMilliseconds:(row["now"] as! NSNumber).doubleValue,snapshot:snapshot),travel=e["travel"] as! [NSNumber]
 for i in 0..<2{assert(abs(output.travel[i]-travel[i].doubleValue)<0.000000001,"\(label):\(frame) travel \(i)");checks+=1}
 assert(output.shot==e["shot"] as! Bool && output.shotLeft==e["shotLeft"] as! Bool,"shot")
 assert(remote.animator.firing==e["firing"] as! Bool && remote.animator.dead==e["dead"] as! Bool && remote.animator.busy==e["busy"] as! Bool,"state \(label):\(frame)")
 assert(remote.animator.tagged==e["tagged"] as? String,"manual tag")
 if let vertices=e["vertices"] as? [[NSNumber]]{let pose=actor.originalPose(blends:output.blends,library:library,aim:output.aim,hiddenBones:output.hiddenBones,figurePitch:output.figurePitch),points=actor.positions(pose:pose);for vertex in vertices{let point=points[vertex[0].intValue],reference=SIMD3(vertex[1].floatValue,vertex[2].floatValue,vertex[3].floatValue),error=simd_distance(point,reference);largest=max(largest,error);assert(error<0.00005,"\(label):\(frame) remote vertex \(vertex[0]) error \(error)");checks+=3}}
 checks+=6
}
print("PASS: \(cases.count) actual remote nC+R6 frames, \(checks) motion/state/pose checks, maxvertex \(largest)m")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-remote-foot-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS);(work/'order.json').write_text(json.dumps(archive.pedestrian_data(archive.GAME/'bmori.dff')[5]))
  subprocess.run(['node',str(work/'reference.js'),str(work/'order.json'),str(work/'reference.json')],cwd=ROOT,check=True)
  names=['NativeActorAnimation','NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeRiderAnimation','NativePedestrianReaction','NativeRemoteFootAnimation']
  (work/'verify.swift').write_text('\n'.join((ROOT/'ios/App'/(name+'.swift')).read_text() for name in names)+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(ROOT),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
