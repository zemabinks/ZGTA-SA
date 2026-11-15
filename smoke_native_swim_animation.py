#!/usr/bin/env python3
"""Compare public 19863.WY swim blends/timing to the native pose helper."""
from pathlib import Path
import subprocess,tempfile
from smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),f=load.factories[49368],g=f.constructor('return globalThis')(),Bytes=f.constructor('return Uint8Array')();
 g.fetch=async url=>{const bytes=fs.readFileSync(path.join(process.cwd(),'local-only/site',url.split('?')[0]));return{ok:true,json:async()=>JSON.parse(bytes),arrayBuffer:async()=>{const array=new Bytes(bytes.length);array.set(bytes);return array.buffer}}};
 const api=load(49368),ped=await api.av(),swim=await api.nN('swim'),lengths={},ready={value:false};
 for(const [block,clips]of [['ped',ped.clips],['swim',swim]])for(const[name,clip]of clips)lengths[block+'/'+name]=clip.duration;
 const prepare=(clip,block)=>clip?{...api.iA(clip),name:block+'/'+clip.name.toLowerCase()}:null;
 const figure={rotation:{x:0}},original=load(19863).WY({ped:{figure},prepare:clip=>prepare(clip,'swim'),named:name=>prepare(ped.clips.get(name),'ped'),loadBlock:()=>{ready.value=true;return Promise.resolve(swim)}});
 const cases=[];
 for(let frame=0;frame<1600;frame++){
  const sequence=[0,1,2,3,4,6,5,6,5,1,7,0],state=sequence[Math.floor(frame/100)%sequence.length],input=state?{state,rate:(Math.sin(frame*.023)+1)/2,pace:1+(frame%70)/200,pitch:Math.sin(frame*.017)*1.1}:null,delta=[1/60,1/50,1/75][frame%3],available=ready.value,blends=[];
  original.draw(delta,input,(clip,time,weight)=>blends.push({clip:clip.name,time,weight}));
  cases.push({input,delta,available,expected:{blends,figurePitch:figure.rotation.x,showing:original.showing}});
  for(let i=0;i<8;i++)await Promise.resolve();
 }
 fs.writeFileSync(process.argv[2],JSON.stringify({lengths,cases}));
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT=r'''
let doc=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [String:Any],lengths=doc["lengths"] as! [String:NSNumber],rows=doc["cases"] as! [[String:Any]]
let swim=NativeSwimAnimation(duration:{lengths[$0]?.doubleValue})
var comparisons=0
for (frame,row)in rows.enumerated(){
 var input:NativeSwimAnimation.Input?
 if let p=row["input"] as? [String:NSNumber]{input=NativeSwimAnimation.Input(state:p["state"]!.intValue,rate:p["rate"]!.doubleValue,pace:p["pace"]!.doubleValue,pitch:p["pitch"]!.doubleValue)}
 let actual=swim.update(delta:(row["delta"] as! NSNumber).doubleValue,input:input,available:row["available"] as! Bool),expected=row["expected"] as! [String:Any],blends=expected["blends"] as! [[String:Any]]
 assert(actual.blends.count==blends.count,"frame \(frame) clip count")
 assert(abs(actual.figurePitch-(expected["figurePitch"] as! NSNumber).doubleValue)<0.000000001,"figure rotation")
 assert(swim.showing==expected["showing"] as! Bool,"showing")
 for(index,blend)in actual.blends.enumerated(){let other=blends[index];assert(blend.clip==other["clip"] as! String,"clip name");assert(abs(blend.time-(other["time"] as! NSNumber).doubleValue)<0.000000001,"frame \(frame) clip time");assert(abs(blend.weight-(other["weight"] as! NSNumber).doubleValue)<0.000000001,"frame \(frame) weight");comparisons+=3};comparisons+=3
}
print("PASS: \(rows.count) original WY swim pose frames, \(comparisons) clip/clock/weight/figure comparisons across all seven states, climb and exit fade")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-swim-animation-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'reference.json')],cwd=ROOT,check=True)
  source=ROOT/'ios/App/NativeSwimAnimation.swift'
  blend='struct NativeSkeletalBlend {enum Operation{case replace};var operation:Operation;var clip:String;var time:Double;var weight:Double}\n'
  helper=FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]
  (work/'verify.swift').write_text(source.read_text()+blend+helper+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
