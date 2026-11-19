#!/usr/bin/env python3

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),root=process.argv[2],load=require(root+'/smoke_vehicle_dynamics').archivedModules(),s=load.factories[19737].toString();
const start=s.indexOf('kO={'),end=s.indexOf(';var kK=',start),step=s.indexOf('step(t,l){',end),crash=s.indexOf('crash(t,r){',step);if([start,end,step,crash].some(x=>x<0))throw Error('Original footstep source boundary changed');
let seed=32186,used=[],events=[];const math=Object.create(Math);math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;const r=seed/4294967296;used.push(r);return r};
const context=vm.createContext({Math:math,n0:load(77287),e:()=>({once:(sample,config)=>events.push({sample,rate:config.rate,gain:config.volume,start:config.start??0})})});
const carrier={exports:{}},factory=vm.runInContext('('+load.factories[24163].toString()+')',context);factory(carrier,carrier.exports,load);context.rh=carrier.exports;
vm.runInContext('let '+s.slice(start,end)+';globalThis.recipes=({'+s.slice(step,crash)+'});',context);
const kinds=['walk','run','sprint','crouch','sneak','unknown','skateL','skateR','skateWalkL','skateWalkR'],frames=[];
for(let i=0;i<4500;i++){const input={kind:kinds[i%kinds.length],mine:i%7!==0,surface:[-1,0,3,4,5,12][Math.floor(i/3)%6],material:[-1,0,1,10,34,62,63,100,178,999][Math.floor(i/11)%10],wading:i%13===0};events=[];used=[];context.input=input;vm.runInContext('recipes.step(input.kind,{at:{},mine:input.mine,ground:{surface:input.surface,material:input.material},wading:input.wading})',context);frames.push({input,random:[...used],expected:events[0]??null})}
const lands=[];for(let i=0;i<100;i++){const input={kind:i%3?'fallLand':'collapse',water:i%2===0};events=[];used=[];context.input=input;vm.runInContext('recipes.land(input.kind,{},input.water)',context);lands.push({input,random:[...used],expected:events[0]})}
const config=JSON.parse(fs.readFileSync(root+'/local-only/site/game/native/audio.json')).footsteps;fs.writeFileSync(process.argv[3],JSON.stringify({config,frames,lands}));
'''
SWIFT=r'''
let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),fixture=try JSONSerialization.jsonObject(with:data) as! [String:Any]
let config=try JSONDecoder().decode(NativeFootstepAudio.Configuration.self,from:JSONSerialization.data(withJSONObject:fixture["config"]!)),audio=NativeFootstepAudio(configuration:config)
var comparisons=0,maximum=0.0
for key in ["frames","lands"]{for (index,row) in (fixture[key] as! [[String:Any]]).enumerated(){let input=row["input"] as! [String:Any],random=row["random"] as! [Double];var cursor=0
 func rng()->Double{precondition(cursor<random.count,"extra RNG");defer{cursor += 1};return random[cursor]}
 let plan:NativeFootstepAudio.Plan?=key=="lands" ? audio.land(input["kind"] as! String,water:input["water"] as! Bool,random:rng):audio.step(input["kind"] as! String,mine:input["mine"] as! Bool,material:input["material"] as? Int,surface:input["surface"] as? Int,wading:input["wading"] as! Bool,random:rng)
 precondition(cursor==random.count,"unused RNG")
 if let expected=row["expected"] as? [String:Any]{guard let plan else{fatalError("Missing plan \(index)")};precondition(plan.sample==expected["sample"] as! String,"sample \(index) \(plan.sample) != \(expected)")
  for (field,actual) in [("rate",plan.rate),("gain",plan.gain),("start",plan.start)]{let error=abs(actual-(expected[field] as! Double));maximum=max(maximum,error);precondition(error<2e-13,"\(index) \(field) error\(error)");comparisons += 1}
 }else{precondition(plan==nil)}
}}
print("PASS original material/phase footstep planner: 4500 steps, 100 landings, \(comparisons) comparisons, max error \(maximum)")
'''
with tempfile.TemporaryDirectory(prefix='zgtasa-foot-audio-') as tmp:
 p=Path(tmp);(p/'fixture.cjs').write_text(JS)
 subprocess.run(['node',str(p/'fixture.cjs'),str(ROOT),str(p/'fixture.json')],check=True)
 (p/'main.swift').write_text((ROOT/'ios/App/NativeFootstepAudio.swift').read_text()+'\n'+SWIFT)
 subprocess.run(['swiftc','-module-cache-path','/private/tmp/zgtasa-foot-audio-modules',str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check'),str(p/'fixture.json')],check=True)
