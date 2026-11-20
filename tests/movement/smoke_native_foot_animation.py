#!/usr/bin/env python3
"""Replay actual 49368.R6 against native root motion and original DFF skinning.

The reference executes the archived client factory with its real Three.js,
ANP3 parser, model loader and animation controller, entirely offline. This is
independent of the older Python animation bake, whose floor/bind assumptions
are intentionally not used for the expected pose.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import json
import subprocess
import tempfile
import tools.assets.prepare_native_animations as archive

ROOT = Path(__file__).resolve().parents[2]
JS = r'''
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require(path.join(process.cwd(),'tests/vehicles/smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),global=load.factories[49368].constructor('return globalThis')();
 const Bytes=load.factories[49368].constructor('return Uint8Array')();
 global.fetch=async url=>{const file=path.join(process.cwd(),'local-only/site',String(url).split('?')[0]);if(!fs.existsSync(file))return {ok:false};const bytes=fs.readFileSync(file);return {ok:true,json:async()=>JSON.parse(bytes.toString()),arrayBuffer:async()=>{const value=new Bytes(bytes.length);value.set(bytes);return value.buffer}}};
 global.setTimeout=(callback,delay)=>{const timer=setTimeout(callback,delay);timer.unref();return timer};global.clearTimeout=clearTimeout;
 load.factories[49368]=load.factories[49368].constructor('return ('+load.factories[49368].toString().replace('get busy(){return!!(', 'get debug(){return {phase:M,tp:tp&&{kind:tp.kind,time:tp.time,weight:tp.weight,ending:tp.ending,down:tp.down}}},get busy(){return!!(')+')')();
 const T=load(85339),api=load(49368),data=await api.av(),order=JSON.parse(fs.readFileSync(process.argv[2]));
 const scenarios=[
  {name:'gaits',frames:620,input:i=>({ratio:i<30?0:i<150?(i-30)/120:i<260?1+(i-150)/110:i<430?2:i<500?Math.max(0,2-(i-430)/35):0,sprint:i>=300&&i<500,pace:i<380?1:1.2,look:Math.sin(i*.019)*.8})},
  {name:'strafe',frames:400,input:i=>({ratio:i<320?1.4:0,strafe:i<340?{x:Math.sin(i*.023)*.9,y:Math.cos(i*.023)*.9}:null,guard:i>=180&&i<260,look:Math.cos(i*.023)*.7})},
  {name:'crouch',frames:380,input:i=>({ratio:i<30?0:i<130?1:i<220?1.6:0,crouch:i>=10&&i<300,strafe:i>=130&&i<220?{x:0,y:-1}:null})},
  {name:'air',frames:420,input:i=>({ratio:i<300?1.8:0,sprint:i<300,air:i>=20&&i<45?'jump':i>=45&&i<65?'glide':i>=130&&i<260?'fall':0,land:i===310?'fallFront':null}),method:i=>i===18?['launch']:null},
  {name:'rolls',frames:430,input:i=>({ratio:i<130?1:0,crouch:i<180}),method:i=>i===15?['roll',-1]:i===95?['roll',1]:i===190?['rollOut',1]:i===330?['knock','koSkidFront']:null},
  {name:'actions',frames:560,input:i=>({ratio:i<320?1.3:0,look:.3}),method:i=>i===10?['act','handsup',true,{rooted:false,blend:6}]:i===70?['rest']:i===100?['act','walk_start',false,{rooted:true,cut:true,once:true}]:i===180?['flinch','flinchL',false]:i===230?['flinch','hitFront',true]:i===340?['die','koFront']:i===500?['revive']:null},
 ];
 for(const weapon of [0,5,8,9,16,22,24,25,26,28,30,34,35,37,41,42])scenarios.push({name:'weapon-'+weapon,weapon,frames:340,
  input:i=>({ratio:i<200?1.3:0,crouch:i>=100&&i<175,strafe:i>=130&&i<220?{x:.65,y:.4}:null,gun:i<300?{pitch:Math.sin(i*.023)*.8,yaw:Math.cos(i*.017)*.4}:null,guard:i>=240&&i<280,block:i>=250&&i<270,poise:i>=285&&i<320,look:Math.sin(i*.02)*.3}),
  control:i=>({aim:i<300,fire:i>=35&&i<90||i>=130&&i<210,held:i<300,pushed:false,ready:!(i>=165&&i<180)}),
  method:i=>i===230?['reload']:i===245?['parry']:i>=35&&i<90||i>=130&&i<210?['fire',true]:null});
 scenarios.push({name:'weapon-switch',weapon:22,frames:430,input:i=>({ratio:.8,gun:{pitch:.5,yaw:-.3},crouch:i>260&&i<330}),control:i=>({aim:true,fire:i%120>20&&i%120<90,held:true}),method:i=>i===140?['arm',34]:i===260?['arm',0]:i===360?['arm',37]:null});
 scenarios.push({name:'swim',warmSwim:true,frames:1600,input:i=>{const state=[1,2,3,4,6,5,6,5,1,7,0][Math.floor(i/100)%11];return {swim:state?{state,rate:(Math.sin(i*.023)+1)/2,pace:1+(i%70)/200,pitch:Math.sin(i*.017)*1.1}:null}},method:i=>i===1200?['die','drown']:i===1320?['revive']:null});
 scenarios.push({name:'flight',warmFlight:true,frames:1800,input:i=>{const state=[1,2,3,4,5,6,7,8,9,10,0,11,12,13,12,13,0,0][Math.floor(i/100)%18];return {fly:state?{state,pitch:Math.sin(i*.019),roll:Math.cos(i*.017)*.8}:null}}});
 const cases=[];
 for(const spec of scenarios){
  const ped=await api.gp('bmori','bmori'),style=await load(66799).r({model:'bmori'},data),steps=[];
  const animator=api.R6(ped,style,data.clips,{onStep:x=>steps.push(x)});if(spec.weapon!==undefined)animator.arm(await load(60662).OP(spec.weapon));if(spec.warmSwim){animator.update(0,{swim:{state:1}});for(let i=0;i<30;i++)await Promise.resolve();}
  if(spec.warmFlight){for(const fly of[{state:1},{state:11},null]){animator.update(0,{fly});for(let i=0;i<40;i++)await Promise.resolve();}}
  const speed={walk:animator.walkSpeed,sprint:animator.sprintSpeed,run:animator.speeds.run};
  for(let frame=0;frame<spec.frames;frame++){
   const method=spec.method?.(frame);if(method){if(method[0]==='arm')animator.arm(await load(60662).OP(method[1]));else animator[method[0]](...method.slice(1));}
   const control=spec.control?.(frame);if(control)animator.control(control);const input=spec.input(frame),delta=[1/60,1/50,1/75][frame%3];steps.length=0;
   const forward=animator.update(delta,input),item={scenario:spec.name,weapon:spec.weapon,warmSwim:spec.warmSwim,warmFlight:spec.warmFlight,frame,delta,input,control,method,speed,expected:{debug:animator.debug,shot:animator.shot,shotLeft:animator.shotLeft,reloading:animator.reloading,firing:animator.firing,gunUp:animator.gunUp,gunShooting:animator.gunShooting,fired:animator.fired,swing:animator.swing,travel:[animator.side,forward],sprint:animator.sprintShare,busy:animator.busy,rolling:animator.rolling,floored:animator.floored,dead:animator.dead,fallen:animator.fallen,acting:animator.acting,acted:animator.acted,stunned:animator.stunned,steps:[...steps]}};
   if(frame%9===0 || method){
    ped.group.updateMatrixWorld(true);let mesh;ped.figure.traverse(x=>{if(x.isSkinnedMesh)mesh=x});mesh.skeleton.update();
    const indices=[0,12,57,113,207,330,500,650,800,821];
    item.expected.vertices=indices.map(index=>{const v=new T.Pq0().fromBufferAttribute(mesh.geometry.attributes.position,order[index]);mesh.applyBoneTransform(index===-1?0:order[index],v).applyMatrix4(mesh.matrixWorld);return [index,v.x,-v.z,v.y]});
   }
   cases.push(item);
  }
  ped.dispose();
 }
 fs.writeFileSync(process.argv[3],JSON.stringify(cases));
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT = r'''
private enum ExactFixtureJSON: Decodable {
 case object([String:ExactFixtureJSON]),array([ExactFixtureJSON]),number(Double),bool(Bool),string(String),null
 init(from decoder:Decoder)throws {
  let c=try decoder.singleValueContainer()
  if c.decodeNil(){self = .null}
  else if let x=try? c.decode(Bool.self){self = .bool(x)}
  else if let x=try? c.decode(Double.self){self = .number(x)}
  else if let x=try? c.decode(String.self){self = .string(x)}
  else if let x=try? c.decode([ExactFixtureJSON].self){self = .array(x)}
  else{self = .object(try c.decode([String:ExactFixtureJSON].self))}
 }
 var any:Any { switch self {case .object(let x):return x.mapValues{ $0.any };case .array(let x):return x.map{ $0.any };case .number(let x):return NSNumber(value:x);case .bool(let x):return x;case .string(let x):return x;case .null:return NSNull()} }
}

let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game"),models=game.appendingPathComponent("native/models")
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:models.appendingPathComponent("animations.clips.bin")))!
let weapons=try NativeFootWeaponAnimation.load(data:Data(contentsOf:game.appendingPathComponent("native/foot-animation.json")))
let definitions=try NativeFootAnimationDefinitions(data:Data(contentsOf:game.appendingPathComponent("world/peds.json")))
guard let device=MTLCreateSystemDefaultDevice(),let actor=NativeSkeletalActor(data:try Data(contentsOf:models.appendingPathComponent("bmori.skel.bin")),vertexCount:822,device:device) else { fatalError("Metal/local bmori rig required") }
let cases=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))).any as! [[String:Any]]
var scenario="",animator:NativeFootAnimation!,comparisons=0,maxMotion:Double=0,maxPose:Float=0
func number(_ dict:[String:Any],_ key:String,_ fallback:Double=0)->Double{(dict[key] as? NSNumber)?.doubleValue ?? fallback}
for item in cases {
 let label=item["scenario"] as! String,frame=item["frame"] as! Int
 if label != scenario {scenario=label;animator=NativeFootAnimation(library:library,style:definitions.style(model:"bmori",library:library),random:{0.37});if let weapon=item["weapon"] as? NSNumber {animator.arm(weapons[weapon.intValue])};if item["warmSwim"] as? Bool == true {var warm=NativeFootAnimation.Input();warm.swim = .init(state:1);_ = animator.update(delta:0,input:warm)};if item["warmFlight"] as? Bool == true{for state in [1,11,0]{var warm=NativeFootAnimation.Input();warm.fly=state==0 ? nil:.init(state:state);_ = animator.update(delta:0,input:warm)}}}
 if let method=item["method"] as? [Any],let name=method.first as? String {
  func side()->Double{(method[1] as! NSNumber).doubleValue}
  switch name {
  case "arm":animator.arm(weapons[(method[1] as! NSNumber).intValue])
  case "reload":_ = animator.reload()
  case "parry":animator.parry()
  case "fire":_ = animator.fire(held:method[1] as! Bool)
  case "launch":_ = animator.launch()
  case "roll":_ = animator.roll(side())
  case "rollOut":_ = animator.rollOut(side())
  case "knock":_ = animator.knock(method[1] as! String)
  case "rest":animator.rest()
  case "flinch":animator.flinch(method[1] as! String,stun:method[2] as! Bool)
  case "die":animator.die(method[1] as! String)
  case "revive":animator.revive()
  case "act":let options=method[3] as! [String:Any];_ = animator.act(method[1] as! String,loop:method[2] as! Bool,rooted:options["rooted"] as? Bool ?? false,cut:options["cut"] as? Bool ?? false,once:options["once"] as? Bool ?? false,blend:number(options,"blend",6))
  default:fatalError("Unexpected fixture method")
  }
 }
 let source=item["input"] as! [String:Any],expected=item["expected"] as! [String:Any]
 var input=NativeFootAnimation.Input();input.ratio=number(source,"ratio");input.sprint=source["sprint"] as? Bool ?? false;input.pace=number(source,"pace",1);input.air=source["air"] as? String;input.land=source["land"] as? String;input.crouch=source["crouch"] as? Bool ?? false;input.guarding=source["guard"] as? Bool ?? false;input.look=number(source,"look");input.block=source["block"] as? Bool ?? false;input.poise=source["poise"] as? Bool ?? false
 if let swim=source["swim"] as? [String:Any]{input.swim=NativeSwimAnimation.Input(state:(swim["state"] as! NSNumber).intValue,rate:number(swim,"rate",1),pace:number(swim,"pace",1),pitch:number(swim,"pitch"))}
 if let fly=source["fly"] as? [String:Any]{input.fly = .init(state:(fly["state"] as! NSNumber).intValue,pitch:number(fly,"pitch"),roll:number(fly,"roll"))}
 if let gun=source["gun"] as? [String:Any]{input.gun=NativeFootAnimation.GunAim(pitch:number(gun,"pitch"),yaw:number(gun,"yaw"))}
 if let c=item["control"] as? [String:Any]{animator.control(NativeFootAnimation.GunControl(fire:c["fire"] as? Bool ?? false,aim:c["aim"] as? Bool ?? false,held:c["held"] as? Bool ?? false,pushed:c["pushed"] as? Bool ?? false,ready:c["ready"] as? Bool ?? true))}
 if let strafe=source["strafe"] as? [String:Any]{input.strafe=SIMD2(number(strafe,"x"),number(strafe,"y"))}
 let result=animator.update(delta:number(item,"delta"),input:input),motion=(expected["travel"] as! [NSNumber]).map(\.doubleValue)
 for axis in 0..<2{let error=abs(result.travel[axis]-motion[axis]);maxMotion=max(maxMotion,error);assert(error<0.000002,"\(label):\(frame) root motion \(axis): \(result.travel) != \(motion)");comparisons+=1}
 assert(abs(result.sprintShare-number(expected,"sprint"))<0.000001,"Sprint share")
 
 for (key,value) in [("busy",animator.busy),("rolling",animator.rolling),("floored",animator.floored),("dead",animator.dead),("fallen",animator.fallen),("acting",animator.acting),("acted",animator.acted),("stunned",animator.stunned),("reloading",animator.reloading),("firing",animator.firing),("gunUp",animator.gunUp),("gunShooting",animator.gunShooting),("fired",animator.fired),("shot",result.shot),("shotLeft",result.shotLeft)] { assert(value == (expected[key] as! Bool),"\(label):\(frame) \(key) native \(value) JS \(expected[key]!), state \(Array(Mirror(reflecting:animator!).children).filter{$0.label == "action"}) JS \(expected["debug"]!)");comparisons+=1 }
 assert(result.steps == expected["steps"] as! [String],"\(label):\(frame) step \(result.steps) != \(expected["steps"]!)")
 if let vertices=expected["vertices"] as? [[NSNumber]] {
  let pose=actor.originalPose(blends:result.blends,library:library,aim:result.aim,hiddenBones:result.hiddenBones,figurePitch:result.figurePitch,figureRoll:result.figureRoll,legBend:result.legBend),points=actor.positions(pose:pose)
  for row in vertices {let actual=points[row[0].intValue],reference=SIMD3(row[1].floatValue,row[2].floatValue,row[3].floatValue),error=simd_distance(actual,reference);maxPose=max(maxPose,error);assert(error<0.0003,"\(label):\(frame) vertex \(row[0]): \(actual) != \(reference); error \(error)");comparisons+=3}
 }
}
print("PASS: \(cases.count) actual browser R6 frames, \(comparisons) root/pose/state comparisons; maximum root error \(maxMotion)m, vertex error \(maxPose)m")
'''

def main():
    with tempfile.TemporaryDirectory(prefix='zgta-foot-animation-') as temporary:
        work = Path(temporary)
        order = archive.pedestrian_data(archive.GAME / 'bmori.dff')[5]
        (work / 'order.json').write_text(json.dumps(order))
        (work / 'reference.js').write_text(JS)
        subprocess.run(['node', str(work / 'reference.js'), str(work / 'order.json'), str(work / 'reference.json')], cwd=ROOT, check=True)
        swift = '\n'.join((ROOT / 'ios/App' / (name + '.swift')).read_text() for name in ['NativeActorAnimation','NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeRiderAnimation']) + SWIFT
        (work / 'verify.swift').write_text(swift)
        subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work / 'verify.swift'),str(ROOT),str(work / 'reference.json')],cwd=ROOT,check=True)

if __name__ == '__main__': main()
