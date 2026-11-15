#!/usr/bin/env python3
"""Run the actual remote-bike packet wrapper against its Swift translation."""
from pathlib import Path
import subprocess,tempfile
from smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),path=require('node:path'),load=require(path.join(process.cwd(),'smoke_vehicle_dynamics')).archivedModules(),factory=load.factories[49368],source=fs.readFileSync('local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js','utf8');
const start=source.indexOf('function(e,t,l,n,r,a){let{more:o,driven:i}=e,s=Array.isArray(l.kit)'),end=source.indexOf('}(null!=(k=A.bike)',start),moduleMatch=source.match(/\bfm=l\((\d+)\)/);
if(start<0||end<0||!moduleMatch)throw Error('Original remote-bike wrapper unavailable');
const original=factory.constructor('d','fm','fg','return('+source.slice(start,end+1)+')')(load(85339),load(Number(moduleMatch[1])),x=>((x%1)+1)%1),state={more:{lean:0},driven:{},built:null,step:null,crank:0,owed:0},models=[{bike:{maxLean:.7431448254773942},restDrop:.2},{bike:{maxLean:.8660254037844386},restDrop:.1}],rows=[];
let sample=null,previous=null,serial=0;
for(let frame=0;frame<3600;frame++){
 const now=1000+frame/60,delta=[1/60,1/50,1/75][frame%3],model=Math.floor(frame/500)%2;
 if(frame%6===0){previous=sample;serial++;const useKit=frame%700<530,mode=Math.floor(frame/80)%3;let kit=useKit?[Math.fround(Math.sin(frame*.013)*.7),Math.fround(Math.sin(frame*.019)),mode,Math.fround((frame*.021)%1),frame%170<20?-1:Math.fround((frame%90)/90)]:null;if(frame%700>480&&kit)kit=kit.slice(0,2);sample={at:(now-(frame%80)/1000)*1000,speed:Math.sin(frame*.007)*27,spin:{y:Math.sin(frame*.011)*.4},health:frame%1000<900?1000:0,kit,serial}}
 const result=original(state,models[model],sample,previous,now*1000,delta).driven;
 rows.push({frame,model,now,delta,maxLean:models[model].bike.maxLean,sample:{serial:sample.serial,time:sample.at/1000,speed:sample.speed,yawRate:sample.spin.y,health:sample.health,kit:sample.kit},previous:previous?{serial:previous.serial,time:previous.at/1000,speed:previous.speed,yawRate:previous.spin.y,health:previous.health,kit:previous.kit}:null,expected:{lean:result.lean,tuck:result.tuck,pedal:result.pedal??null,crank:result.crank??null,hop:result.hop}});
}
fs.writeFileSync(process.argv[2],JSON.stringify(rows));
'''
SWIFT=r'''
let rows=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [[String:Any]],bike=NativeRemoteBikeAnimation()
var maximum:Double=0
func sample(_ p:[String:Any])->NativeRemoteBikeAnimation.Sample{func n(_ k:String)->Double{(p[k] as! NSNumber).doubleValue};return .init(serial:n("serial"),time:n("time"),speed:n("speed"),yawRate:n("yawRate"),health:n("health"),kit:(p["kit"] as? [NSNumber])?.map(\.doubleValue))}
for row in rows{let expected=row["expected"] as! [String:Any],previous=(row["previous"] as? [String:Any]).map(sample),actual=bike.update(model:String(describing:row["model"]!),maxLean:(row["maxLean"] as! NSNumber).doubleValue,now:(row["now"] as! NSNumber).doubleValue,delta:(row["delta"] as! NSNumber).doubleValue,sample:sample(row["sample"] as! [String:Any]),previous:previous)
 for (key,value)in[("lean",actual.lean),("tuck",actual.tuck),("hop",actual.hop)]{let error=abs(value-(expected[key] as! NSNumber).doubleValue);maximum=max(maximum,error);assert(error<0.000000001,"\(row["frame"]!) \(key):\(error)")}
 assert(actual.pedal==(expected["pedal"] as? NSNumber)?.intValue,"pedal")
 if let crank=actual.crank{let error=abs(crank-(expected["crank"] as! NSNumber).doubleValue);maximum=max(maximum,error);assert(error<0.000000001,"crank \(error)")}else{assert(expected["crank"] is NSNull)}
}
print("PASS: \(rows.count) original remote-bike packet prediction/lean/tuck/pedal/crank/hop frames; maxerror \(maximum)")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-remote-bike-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'reference.json')],cwd=ROOT,check=True)
  (work/'verify.swift').write_text((ROOT/'ios/App/NativeRemoteBikeAnimation.swift').read_text()+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
