#!/usr/bin/env python3
"""Replay the actual 54205.ap public flight presenter against native Swift."""
from pathlib import Path
import subprocess,tempfile
from smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 g.fetch=async url=>{if(String(url).includes('jetpack.'))return{ok:true,arrayBuffer:async()=>new Bytes(1).buffer};const bytes=fs.readFileSync(path.join(process.cwd(),'local-only/site',url.split('?')[0]));return{ok:true,json:async()=>JSON.parse(bytes),arrayBuffer:async()=>{const a=new Bytes(bytes.length);a.set(bytes);return a.buffer}}};
 const T=load(85339),api=load(49368),ped=await api.av(),para=await api.nN('parachute'),lengths={};
 for(const[block,clips]of[['ped',ped.clips],['parachute',para]])for(const[name,clip]of clips)lengths[block+'/'+name]=clip.duration;
 const prepare=(clip,block)=>clip?{...api.iA(clip),name:block+'/'+clip.name.toLowerCase()}:null;
 const figure=new T.YJl,group=new T.YJl,parent=new T.YJl;parent.add(group);group.add(figure);
 const bones=new Map([3,41,51].map(id=>[id,new T.YJl]));for(const bone of bones.values())figure.add(bone);
 let canopy,jetSound=null;
 const jet=new T.YJl;jet.name='fixture-jetpack';for(const name of['jetball1','jetball2']){const ball=new T.YJl;ball.name=name;jet.add(ball)}
 const flightLoad=id=>id===88711?{yK:()=>({userData:{model:jet}}),XC:()=>new Map}:id===78315?{A:()=>null}:id===52528?{nk:()=>null}:load(id);flightLoad.d=load.d;
 const flightExports={};load.factories[54205](null,flightExports,flightLoad);flightExports.iv({sounds:{loop:(id,sound)=>{jetSound=sound}}});
 const build=async()=>{const root=new T.YJl,figure=new T.YJl;root.add(figure);return canopy={group:root,figure,bones:new Map,dispose(){}}};
 const original=flightExports.ap({ped:{group,figure,bones},prepare:clip=>prepare(clip,'parachute'),named:name=>prepare(ped.clips.get(name),'ped'),sample:()=>false,loadBlock:()=>Promise.resolve(para),build});
 // Native loads the whole archived clip library eagerly; warm the public
 // asynchronous block/canopy exactly once before comparing ready state.
 original.draw(0,{state:1,pitch:0,roll:0},()=>{});for(let i=0;i<12;i++)await Promise.resolve();original.draw(0,{state:11,pitch:0,roll:0},()=>{});for(let i=0;i<24;i++)await Promise.resolve();original.draw(0,null,()=>{});
 const rows=[],states=[1,2,3,4,5,6,7,8,9,10,0,11,12,13,12,13,11,0];
 for(let frame=0;frame<5400;frame++){
  const state=states[Math.floor(frame/100)%states.length],delta=[1/60,1/50,1/75][frame%3],input=state?{state,pitch:Math.sin(frame*.023)*1.2,roll:Math.sin(frame*.017)*.8}:null;
  const position=[Math.sin(frame*.003)*40,frame*.021,18+Math.cos(frame*.005)*3],heading=Math.sin(frame*.002)*2;
  group.position.set(position[0],position[2],-position[1]);group.rotation.y=-heading;group.updateWorldMatrix(true,true);
  for(const id of[41,51])bones.get(id).quaternion.identity();const blends=[];
  if(input||original.showing)original.draw(delta,input,(clip,time,weight)=>blends.push({clip:clip.name,time,weight}));original.bend();
  const attached=bones.get(3).getObjectByName('fixture-jetpack');rows.push({frame,delta,input,position,heading,expected:{blends,pitch:figure.rotation.x,roll:figure.rotation.y,bend:bones.get(41).quaternion.toArray(),jet:attached?.visible?{pitch:attached.getObjectByName('jetball1').rotation.x,leftRoll:attached.getObjectByName('jetball1').rotation.y,rightRoll:attached.getObjectByName('jetball2').rotation.y,sound:jetSound}:null,canopy:canopy.group.visible?{scale:canopy.group.scale.x,pitch:canopy.figure.rotation.x,roll:canopy.figure.rotation.y}:null}});
 }
 fs.writeFileSync(process.argv[2],JSON.stringify({lengths,rows}));original.dispose();
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT=r'''
let doc=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [String:Any],lengths=doc["lengths"] as! [String:NSNumber],rows=doc["rows"] as! [[String:Any]],flight=NativeFlightAnimation(duration:{lengths[$0]?.doubleValue})
var maximum:Double=0,checks=0
func n(_ p:[String:Any],_ k:String)->Double{(p[k] as! NSNumber).doubleValue}
func compare(_ a:Double,_ b:Double,_ label:String){let error=abs(a-b);maximum=max(maximum,error);assert(error<0.000000002,"\(label): \(a) vs \(b), error \(error)");checks+=1}
for row in rows {
 let input=(row["input"] as? [String:Any]).map{NativeFlightAnimation.Input(state:Int(n($0,"state")),pitch:n($0,"pitch"),roll:n($0,"roll"))},p=(row["position"] as! [NSNumber]).map(\.doubleValue),expected=row["expected"] as! [String:Any]
 let actual=flight.update(delta:n(row,"delta"),input:input,position:SIMD3(p[0],p[1],p[2]),heading:n(row,"heading")),blends=expected["blends"] as! [[String:Any]]
 assert(actual.blends.count==blends.count,"frame \(row["frame"]!) blend count")
 for(index,blend)in actual.blends.enumerated(){assert(blend.clip==blends[index]["clip"] as! String);compare(blend.time,n(blends[index],"time"),"clip time");compare(blend.weight,n(blends[index],"weight"),"clip weight")}
 compare(actual.figurePitch,n(expected,"pitch"),"pitch");compare(actual.figureRoll,n(expected,"roll"),"roll")
 let q=abs(actual.bend.x)<0.001 && abs(actual.bend.y)<0.001 ? simd_quatd(vector:SIMD4(0,0,0,1)):simd_quatd(angle:actual.bend.x,axis:SIMD3(0,0,1))*simd_quatd(angle:actual.bend.y,axis:SIMD3(0,1,0)),want=(expected["bend"] as! [NSNumber]).map(\.doubleValue)
 for index in 0..<4{compare(q.vector[index],want[index],"leg bend frame \(row["frame"]!)")}
 if let jet=actual.jet{let value=expected["jet"] as! [String:Any];compare(jet.pitch,n(value,"pitch"),"jet pitch");compare(jet.leftRoll,n(value,"leftRoll"),"jet left roll");compare(jet.rightRoll,n(value,"rightRoll"),"jet right roll");assert(jet.sound==value["sound"] as! String)}else{assert(expected["jet"] is NSNull,"jet visibility")}
 if let canopy=actual.canopy,canopy.visible {let value=expected["canopy"] as! [String:Any];compare(canopy.scale,n(value,"scale"),"canopy scale");compare(canopy.pitch,n(value,"pitch"),"canopy pitch");compare(canopy.roll,n(value,"roll"),"canopy roll")}else{assert(expected["canopy"] is NSNull,"frame \(row["frame"]!) canopy visibility")}
}
print("PASS: \(rows.count) original parachute/jetpack pose frames, \(checks) blend/clock/figure/canopy/leg-pendulum checks; maxerror \(maximum)")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-flight-animation-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'reference.json')],cwd=ROOT,check=True)
  blend='struct NativeSkeletalBlend {enum Operation{case replace};var operation:Operation;var clip:String;var time:Double;var weight:Double}\n'
  (work/'verify.swift').write_text((ROOT/'ios/App/NativeFlightAnimation.swift').read_text()+blend+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
