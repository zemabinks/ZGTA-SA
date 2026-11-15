#!/usr/bin/env python3
"""Replay the actual archived weather voice mixer and thunder function."""
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),{archivedModules}=require(process.argv[2]+'/smoke_vehicle_dynamics'),load=archivedModules();
const folder=process.argv[2]+'/local-only/site/_next/static/chunks',text=fs.readdirSync(folder).filter(x=>x.endsWith('.js')).map(x=>fs.readFileSync(folder+'/'+x,'utf8')).find(x=>x.includes('((e,t,l)=>{let r=n();'));
const start=text.indexOf('((e,t,l)=>{let r=n();'),end=text.indexOf('})(K,P,ep.y)',start);
const thunderStart=text.indexOf('e&&(e=>{let t=Math.min(1,yg(20*Math.log10'),thunderEnd=text.indexOf('})(e)',thunderStart);
let events=[],used=[],seed=7342;
const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;const x=seed/4294967296;used.push(x);return x};
const voice={ready:samples=>events.push({kind:'ready',samples}),drop:id=>events.push({kind:'drop',id}),
 hold:(id,sample,p)=>events.push({kind:'hold',id,sample,rate:p.rate,gain:p.volume,pan:p.pan}),
 once:(sample,p)=>events.push({kind:'once',sample,rate:p.rate,gain:p.volume,pan:p.pan,rise:p.rise})};
const math=Object.create(Math);math.random=random;
const context=vm.createContext({mx:load(93265),Math:math,voice});
const constants=text.slice(text.indexOf('ys=["105_1"'),text.indexOf(';function yj(',text.indexOf('ys=["105_1"')));
vm.runInContext('let '+constants+';let o=0,s=0,i=0,X=false,Y=-100,$=-100,J=false,Q=2,Z=-100,ee=-100,et=false,el=false,en=1,er=1,ea=-100,eo=false,ei=0,es=false,v=0,b=0;'+
 'let G=yf.map((pan,index)=>({pan,first:true,swapAt:0,names:["weather:rain"+index+"a","weather:rain"+index+"b"],wind:"weather:wind"+index}));'+
 'let V={rate:1,volume:0,pan:0},K={rate:1,volume:0,pan:0,rise:0};let n=()=>voice;'+
 'let ec=(e,t,l,n,r)=>{V.volume=yg(n);V.pan=r;e.hold(t,l,V)},eu=(e,t,l,n,r,a=0)=>{K.rate=l;K.volume=n;K.pan=r;K.rise=a;e.once(t,K)},'+
 'ed=e=>{if(J)for(let t of G)for(let l of t.names)e.drop(l);if(el)for(let t of G)e.drop(t.wind);eo&&e.drop("weather:storm");J=el=eo=false;Y=$=Z=ee=ea=-100};'+
 'globalThis.mix='+text.slice(start,end+2)+';globalThis.thunder=(ticks)=>{b=ticks;let e=voice;'+text.slice(thunderStart,thunderEnd+5)+'};',context);
const frames=[];
for(let index=0;index<1500;index++){
 const input={milliseconds:(index+1)*1000/30,outdoors:index%300<250,altitude:(index*17)%700,
 rain:index<400?Math.min(.9,index/150):index<800?Math.max(0,.9-(index-400)/150):0,
 wind:index<1000?.85:index<1200?1.5:0,sand:index>=700&&index<1200?.7:0};
 events=[];used=[];context.input=input;
 vm.runInContext('o=input.rain;s=input.wind;i=input.sand;mix(input.milliseconds,input.outdoors,input.altitude)',context);
 frames.push({input,random:[...used],events});
}
const claps=[];
for(const ticks of [0,1,8,19,20,4,15,20,20]){events=[];context.ticks=ticks;vm.runInContext('thunder(ticks)',context);claps.push({ticks,events})}
fs.writeFileSync(process.argv[3],JSON.stringify({frames,claps}));
'''
SWIFT=r'''
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
let mixer=NativeWeatherAudio();var events:[NativeWeatherAudio.Event]=[],comparisons=0,maximum=0.0
mixer.onEvents={events += $0}
func check(_ a:Double,_ e:Double,_ label:String){comparisons += 1;maximum=max(maximum,abs(a-e));precondition(abs(a-e)<2e-12,label+": \(a) != \(e)")}
func verify(_ expected:[[String:Any]],_ label:String){
 precondition(events.count==expected.count,"\(label) event count \(events.count) != \(expected.count)")
 for (actual,row) in zip(events,expected){
  precondition(actual.kind==row["kind"] as! String,label+" kind")
  if let id=row["id"] as? String{precondition(actual.id==id,label+" id")}
  if let sample=row["sample"] as? String{precondition(actual.sample==sample,label+" sample")}
  if let samples=row["samples"] as? [String]{precondition(actual.samples==samples,label+" preload")}
  for (key,value) in [("rate",actual.rate),("gain",actual.gain),("pan",actual.pan),("rise",actual.rise)]{
   if let number=row[key] as? Double{check(value,number,label+" "+key)}
  }
 }
}
for (index,frame) in (fixture["frames"] as! [[String:Any]]).enumerated(){
 let input=frame["input"] as! [String:Any],random=frame["random"] as! [Double];var cursor=0;events=[]
 mixer.step(milliseconds:input["milliseconds"] as! Double,outdoors:input["outdoors"] as! Bool,altitude:input["altitude"] as! Double,
  rain:input["rain"] as! Double,wind:input["wind"] as! Double,sand:input["sand"] as! Double,
  random:{precondition(cursor<random.count,"extra random call");defer{cursor += 1};return random[cursor]})
 precondition(cursor==random.count,"unused random calls");verify(frame["events"] as! [[String:Any]],"frame\(index)")
}
for (index,clap) in (fixture["claps"] as! [[String:Any]]).enumerated(){
 events=[];mixer.thunder(durationTicks:clap["ticks"] as! Int,serial:index);verify(clap["events"] as! [[String:Any]],"thunder\(index)")
}
print("PASS: 1500 original weather-mixer frames + 9 thunder events; \(comparisons) comparisons, max error \(maximum)")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-weather-audio-') as tmp:
  work=Path(tmp);js=work/'reference.js';js.write_text(JS);fixture=work/'reference.json'
  subprocess.run(['node',str(js),str(ROOT),str(fixture)],check=True)
  swift=work/'verify.swift';swift.write_text((ROOT/'ios/App/NativeWeatherAudio.swift').read_text()+SWIFT)
  subprocess.run(['swift','-module-cache-path',str(work/'modules'),str(swift),str(fixture)],check=True)
if __name__=='__main__':main()
