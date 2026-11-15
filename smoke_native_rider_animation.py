#!/usr/bin/env python3
"""Replay original bA.es/ec seated/bike animation selection without a GPU."""
from pathlib import Path
import subprocess,tempfile
from smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],global=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 global.fetch=async url=>{const bytes=fs.readFileSync(path.join(process.cwd(),'local-only/site',url.split('?')[0]));return{ok:true,json:async()=>JSON.parse(bytes),arrayBuffer:async()=>{const value=new Bytes(bytes.length);value.set(bytes);return value.buffer}}};
 const T=load(85339),api=load(49368),ped=await api.av(),catalog=JSON.parse(fs.readFileSync('local-only/site/game/native/seating.json')).models,lengths={},cases=[];
 const source=fs.readFileSync('local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js','utf8'),start=source.indexOf('es=(e,t)=>{var l,n,r,a,o,s,c;'),end=source.indexOf(',eu=function(e)',start),original=source.slice(start,end);
 if(start<0||end<0)throw Error('Original rider es/ec not found');
 async function clip(name){if(!name)return null;const[block,key]=name.split('/'),clips=block==='ped'?ped.clips:await api.nN(block),raw=clips.get(key);if(!raw||!(raw.duration>0))return null;lengths[name]=raw.duration;return{name,duration:raw.duration}}
 for(const id of [420,411,403,446,571,468,448,463,481,509,510,519,537])for(const passenger of [false,true]){
  const config={astride:catalog[id].astride,clips:catalog[id].clips,passenger,side:passenger?1:-1},clips=Object.fromEntries(await Promise.all(Object.entries(config.clips).map(async([role,name])=>[role,await clip(name)])));
  const h={astride:config.astride,sit:[clips.sit,clips.passenger],dead:[clips.deadLeft,clips.deadRight],steer:{left:clips.left,right:clips.right,slowLeft:clips.slowLeft,slowRight:clips.slowRight},ride:{ride:clips.sit,still:clips.still,left:clips.left,right:clips.right,fwd:clips.forward,back:clips.backward,passenger:clips.passenger,pedal:clips.pedal,sprint:clips.sprint,bunnyhop:clips.bunnyhop}};
  const create=factory.constructor('d','h','passenger',`const bN=(a,b,x)=>d.cj9.smoothstep(x,a,b),m=[{at:new d.Pq0}],f=passenger?{at:new d.Pq0,side:1,rear:true}:m[0],C=new d.Pq0,B={still:1,lean:0,tuck:0,steer:0,pedal:0,sprint:0,hop:0};f.side??=-1;let J=0,Z=0,result;const i={set:(clip,time)=>{result={base:clip?.name??null,time,mixes:[]}},mix:(clip,time,weight)=>{if(clip&&weight>.001)result.mixes.push({clip:clip.name,time,weight:Math.min(1,weight)})}};let ${original};return(dt,input)=>{es(dt,input);return result}`);
  const step=create(T,h,passenger);
  for(let frame=0;frame<620;frame++){
   const input={speed:frame<60?0:Math.sin(frame*.01)*30,steer:Math.sin(frame*.031)*.8,lean:Math.sin(frame*.019)*.7,tuck:Math.cos(frame*.023),pedal:frame%200<60?0:frame%200<140?1:2,hop:frame%150<20?frame%150/20:frame%150<35?-1:0,dead:frame>=560};
   if(frame>=350)input.crank=frame*.021-7;
   const delta=[1/60,1/50,1/75][frame%3];cases.push({id,passenger,config,input,delta,expected:step(delta,input)});
  }
 }
 fs.writeFileSync(process.argv[2],JSON.stringify({lengths,cases}));
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT=r'''
let doc=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [String:Any],lengths=doc["lengths"] as! [String:NSNumber],rows=doc["cases"] as! [[String:Any]]
var current="",rider:NativeRiderAnimation!,comparisons=0
for (frame,row)in rows.enumerated(){
 let key="\(row["id"]!)-\(row["passenger"]!)",c=row["config"] as! [String:Any],p=row["input"] as! [String:Any],expected=row["expected"] as! [String:Any]
 if current != key{current=key;rider=NativeRiderAnimation(duration:{lengths[$0]?.doubleValue})}
 let configuration=NativeRiderAnimation.Configuration(astride:c["astride"] as! Bool,clips:c["clips"] as! [String:String],passenger:c["passenger"] as! Bool,side:(c["side"] as! NSNumber).intValue)
 func n(_ key:String)->Double{(p[key] as! NSNumber).doubleValue}
 let input=NativeRiderAnimation.Input(speed:n("speed"),steer:n("steer"),lean:n("lean"),tuck:n("tuck"),pedal:(p["pedal"] as? NSNumber)?.intValue,crank:(p["crank"] as? NSNumber)?.doubleValue,hop:n("hop"),dead:p["dead"] as! Bool)
 let actual=rider.update(delta:(row["delta"] as! NSNumber).doubleValue,configuration:configuration,input:input),mixes=expected["mixes"] as! [[String:Any]]
 assert(actual.base==expected["base"] as? String,"\(key):\(frame) base")
 assert(abs(actual.time-(expected["time"] as! NSNumber).doubleValue)<0.000000001,"base clock")
 assert(actual.mixes.count==mixes.count,"\(key):\(frame) mix count \(actual.mixes.count) expected \(mixes.count)")
 for(index,mix)in actual.mixes.enumerated(){let other=mixes[index];assert(mix.clip==other["clip"] as! String,"clip");assert(abs(mix.time-(other["time"] as! NSNumber).doubleValue)<0.000000001,"clock");assert(abs(mix.weight-(other["weight"] as! NSNumber).doubleValue)<0.000000001,"\(key):\(frame) weight");comparisons+=3};comparisons+=3
}
print("PASS: \(rows.count) original bA seated/bike pose frames, \(comparisons) clip/clock/weight comparisons across 13 vehicle families and passenger seats")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-rider-animation-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'reference.json')],cwd=ROOT,check=True)
  source=ROOT/'ios/App/NativeRiderAnimation.swift'
  (work/'verify.swift').write_text(source.read_text()+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
