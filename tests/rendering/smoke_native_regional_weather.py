#!/usr/bin/env python3
"""Compare native weather clock/override transitions to the actual vE factory."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),source=fs.readFileSync(process.argv[2],'utf8'),data=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
const start=source.indexOf('vE=function(){let e={from:0,to:0,shift:0}'),stop=source.indexOf('}(),vR=',start);
const context={mx:{k8:data.sequences}};vm.createContext(context);const original=vm.runInContext('('+source.slice(start+3,stop+1)+')()',context);
const cases=[],at=1700000000000;
const regions=[[1500,-1750],[-1700,200],[1500,1500],[0,1800],[0,0],[1000,910],[-850,1280],[-1430,-580],[250,-850],[3000,-3000]];
function run(enabled,time,pos,from=10,to=10,blend=1,delta=1/60){pos=pos.map(Math.fround);blend=Math.fround(blend);delta=Math.fround(delta);cases.push({enabled,time,pos,from,to,blend,delta,expected:{...original.pick(enabled,time,...pos,from,to,blend,delta)}})}
for(let minute=0;minute<36;minute++)for(let r=0;r<regions.length;r++)run(true,at+minute*60000+r*3000,regions[r]);
for(let i=0;i<280;i++)run(false,at+2160000+i*17,regions[i%regions.length],0,8,1);
for(let i=0;i<60;i++)run(true,at+2200000+i*17,regions[i%regions.length]);
for(let i=0;i<40;i++)run(false,at+2220000+i*17,regions[0],1,19,i/39);
for(const time of [0,1000,59999,60000,120000,60000000,at,at+123456789])run(true,time,regions[0]);
for(let i=0;i<100;i++)run(i%7<4,at+i*125000,regions[i%regions.length],i%23,(i*7)%23,i%3===0?.5:1,Math.fround(.1));
fs.writeFileSync(process.argv[4],JSON.stringify(cases));
'''
SWIFT=r'''
let weather=try NativeRegionalWeather(data:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]]
for (index,item) in cases.enumerated(){
 let p=(item["pos"] as! [NSNumber]).map(\.floatValue)
 let actual=weather.pick(automatic:item["enabled"] as! Bool,epochMilliseconds:item["time"] as! Double,position:SIMD2(p[0],p[1]),manualFrom:item["from"] as! Int,manualTo:item["to"] as! Int,manualBlend:(item["blend"] as! NSNumber).floatValue,delta:(item["delta"] as! NSNumber).floatValue)
 let expected=item["expected"] as! [String:Any]
 assert(actual.from==expected["from"] as! Int && actual.to==expected["to"] as! Int,"weather pair differs frame \(index)")
 assert(abs(actual.blend-(expected["shift"] as! NSNumber).floatValue)<0.000001,"weather blend differs frame \(index)")
}
assert(NativeRegionalWeather.region(x:1500,y:1500)=="lv")
assert(NativeRegionalWeather.region(x:0,y:1800)=="desert")
assert(NativeRegionalWeather.region(x:-1700,y:200)=="sf")
assert(NativeRegionalWeather.region(x:1500,y:-1750)=="la")
print("PASS: \(cases.count) actual JS regional weather frames: all regions/boundaries, minute transitions, clock jumps,4 s override release and manual transition precedence")
'''

def main():
 chunks=ROOT/'local-only/site/_next/static/chunks'
 source=next(p for p in chunks.glob('*.js') if 'vE=function(){let e={from:0,to:0,shift:0}' in p.read_text())
 data=ROOT/'local-only/site/game/native/environment.json'
 with tempfile.TemporaryDirectory(prefix='zgta-regional-weather-') as tmp:
  work=Path(tmp);js=work/'reference.js';js.write_text(JS);reference=work/'reference.json'
  subprocess.run(['node',str(js),str(source),str(data),str(reference)],check=True)
  swift=work/'verify.swift';swift.write_text(''.join((ROOT/f'ios/App/{n}.swift').read_text() for n in ['ServerAddress','NativeRegionalWeather'])+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(swift),str(data),str(reference)],check=True)
if __name__=='__main__':main()
