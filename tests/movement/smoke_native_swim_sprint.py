#!/usr/bin/env python3
"""Compare native swimming/oxygen and sprint budgets with actual archived JS."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
JS = r'''
const fs=require('node:fs'),{archivedModules}=require(process.argv[2]+'/smoke_vehicle_dynamics'),load=archivedModules();
const originalSprint=load(34719),originalSwim=load(19863),T=load(85339);
const sprint=[];
for(const mode of ['foot','bike','water','under']){
 const controller=originalSprint.jZ();let value=150,laden=false,tireless=false;
 const budget={get left(){return value+90},take:amount=>amount<=0||!laden&&(tireless||!(value<=-150)&&(value=Math.max(-150,value-amount/3),true))};
 const frames=[];
 for(let i=0;i<2400;i++){
  const ticks=[.5,1,1.5,2][i%4],tapped=i%12===0,held=i%200<160;
  laden=i>=200&&i<240;tireless=i>=500&&i<600;
  const reset=i===1500;if(reset){controller.reset();value=150}
  const rest=i%200>=160?ticks*.5:0;value=Math.min(150,value+rest);
  const result=controller.control(originalSprint.xC[mode],ticks,tapped,held,budget);
  frames.push({ticks,tapped,held,laden,tireless,rest,reset,result,counter:controller.counter,pace:controller.result(originalSprint.xC[mode]),stamina:value});
 }
 sprint.push({mode,frames});
}
const swim=[],scenarios=[
 {name:'tread',steps:360,depth:1.8},
 {name:'breast',steps:360,depth:2,push:1},
 {name:'crawl',steps:360,depth:2,push:1,sprint:1.3},
 {name:'dive',steps:360,depth:2,push:1,diveAt:40},
 {name:'underwater',steps:480,depth:5,push:1,pitch:-.4,sprint:1.1},
 {name:'glide',steps:360,depth:5},
 {name:'surface',steps:360,depth:5,push:1,pitch:1.2,surfaceAt:90},
 {name:'oxygen_empty',steps:1800,depth:5,push:1,pitch:0},
 {name:'dead',steps:240,depth:2,dead:true},
 {name:'jump_out',steps:180,depth:2,jumpAt:40},
 {name:'ledge_haul',steps:180,depth:2,jumpAt:40,ledge:true},
 {name:'shallow_ground',steps:180,depth:2,groundAt:30},
 {name:'leave_water',steps:180,depth:2,exitAt:60},
 {name:'clip_speeds',steps:300,depth:2,push:1,speeds:{breast:1.97,crawl:3.14,under:2.1}},
];
const v=x=>new T.Pq0(...x),a=x=>[x.x,x.y,x.z];
for(const scenario of scenarios){
 const controller=originalSwim.dp(),initial={velocity:[.2,0,-.4],rising:-3,depth:scenario.depth};
 controller.enter(v(initial.velocity),initial.rising,initial.depth);if(scenario.speeds)controller.setSpeeds(scenario.speeds);
 const frames=[];
 for(let i=0;i<scenario.steps;i++){
  const delta=[1/60,1/30,1/120][i%3],depth=i>=scenario.exitAt?null:i>=scenario.surfaceAt?1.2:i>=scenario.groundAt?1.5:scenario.depth;
  const input={delta,depth,push:scenario.push??0,sprint:scenario.sprint??0,pitch:scenario.pitch??0,dive:i===scenario.diveAt,
   grounded:i>=scenario.groundAt,heading:(i*.003)%6.28,feet:[1,2,3],jump:i===scenario.jumpAt,ledge:!!scenario.ledge,dead:!!scenario.dead};
  controller.steer(input);
  const result=controller.on?controller.step(delta,{depth,grounded:input.grounded,heading:input.heading,feet:v(input.feet),jump:input.jump,
    ledge:()=>input.ledge?v([2,3,4]):null,dead:input.dead}):null;
  if(!controller.on)controller.ashore(delta);
  frames.push({input,result:result?{move:a(result.move),rise:result.rise,hurt:result.hurt}:null,
    state:{on:controller.on,state:controller.state,pitch:controller.pitch,ratio:controller.ratio,pace:controller.pace,
      turns:controller.turns,under:controller.under,breath:controller.breath,splash:controller.splash,hauled:controller.hauled?a(controller.hauled):null}});
 }
 swim.push({name:scenario.name,initial,speeds:scenario.speeds,frames});
}
fs.writeFileSync(process.argv[3],JSON.stringify({sprint,swim}));
'''
SWIFT = r'''
func vector(_ raw: Any) -> SIMD3<Double> { let row=raw as! [Double];return SIMD3(row[0],row[1],row[2]) }
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var comparisons=0,maximum=0.0,sprintFrames=0,swimFrames=0
func check(_ actual: Double,_ expected: Double,_ name: String){
 comparisons += 1;maximum=max(maximum,abs(actual-expected));precondition(actual.isFinite && abs(actual-expected)<2e-10,"\(name): \(actual) != \(expected)")
}
func checkVector(_ actual: SIMD3<Double>,_ raw: Any,_ name: String){let e=vector(raw);for i in 0..<3{check(actual[i],e[i],name)}}
for scenario in fixture["sprint"] as! [[String:Any]]{
 let controller=NativeSprintController();var stamina=NativeStamina()
 let mode:NativeSprintController.Mode=["foot":.foot,"bike":.bike,"water":.water,"under":.underwater][scenario["mode"] as! String]!
 let profile=NativeSprintController.Profile.forMode(mode)
 for frame in scenario["frames"] as! [[String:Any]]{
  if frame["reset"] as! Bool{controller.reset();stamina.reset()}
  stamina.laden=frame["laden"] as! Bool;stamina.tireless=frame["tireless"] as! Bool;stamina.rest(frame["rest"] as! Double)
  let result=controller.control(profile,ticks:frame["ticks"] as! Double,tapped:frame["tapped"] as! Bool,held:frame["held"] as! Bool,
    staminaLeft:stamina.left,take:{stamina.take($0)})
  check(result,frame["result"] as! Double,"sprint result");check(controller.counter,frame["counter"] as! Double,"counter")
  check(controller.result(profile),frame["pace"] as! Double,"pace");check(stamina.value,frame["stamina"] as! Double,"stamina");sprintFrames += 1
 }
}
for scenario in fixture["swim"] as! [[String:Any]]{
 let controller=NativeSwimController(),initial=scenario["initial"] as! [String:Any]
 controller.enter(velocity:vector(initial["velocity"]!),rising:initial["rising"] as! Double,depth:initial["depth"] as! Double)
 if let speed=scenario["speeds"] as? [String:Double]{controller.setSpeeds(breast:speed["breast"],crawl:speed["crawl"],under:speed["under"])}
 for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated(){
  let input=frame["input"] as! [String:Any],state=frame["state"] as! [String:Any],delta=input["delta"] as! Double
  let label="\(scenario["name"]!)/\(index)"
  controller.steer(push:input["push"] as! Double,sprint:input["sprint"] as! Double,dive:input["dive"] as! Bool,pitch:input["pitch"] as! Double)
  let result=controller.on ? controller.step(delta:delta,depth:input["depth"] as? Double,grounded:input["grounded"] as! Bool,
   heading:input["heading"] as! Double,feet:vector(input["feet"]!),jump:input["jump"] as! Bool,
   ledge:{input["ledge"] as! Bool ? SIMD3(2,3,4) : nil},dead:input["dead"] as! Bool) : nil
  if !controller.on{controller.ashore(delta)}
  if let expected=frame["result"] as? [String:Any]{
   precondition(result != nil,label+" missing result");checkVector(result!.move,expected["move"]!,label+" move")
   check(result!.rise,expected["rise"] as! Double,label+" rise");check(result!.hurt,expected["hurt"] as! Double,label+" hurt")
  }else{precondition(result == nil,label+" unexpected result")}
  precondition(controller.on == state["on"] as! Bool,label+" active")
  precondition((controller.on ? controller.state.rawValue : 0) == state["state"] as! Int,label+" state")
  precondition(controller.turns == state["turns"] as! Bool && controller.under == state["under"] as! Bool,label+" turn/under")
  check(controller.pitch,state["pitch"] as! Double,label+" pitch");check(controller.ratio,state["ratio"] as! Double,label+" ratio")
  check(controller.pace,state["pace"] as! Double,label+" pace");check(controller.breath,state["breath"] as! Double,label+" breath")
  precondition(controller.consumeSplash() == state["splash"] as! Bool,label+" splash")
  if state["hauled"] is NSNull{precondition(controller.hauled == nil,label+" haul")}else{checkVector(controller.hauled!,state["hauled"]!,label+" haul")}
  swimFrames += 1
 }
}
print("PASS: \(sprintFrames) sprint/stamina + \(swimFrames) swimming/oxygen frames, \(comparisons) actual-JS comparisons; max error \(maximum)")
'''

def main():
    with tempfile.TemporaryDirectory(prefix='zgta-swim-sprint-') as temporary:
        work=Path(temporary)
        js=work/'reference.js';js.write_text(JS)
        fixture=work/'reference.json'
        subprocess.run(['node',str(js),str(ROOT),str(fixture)],check=True)
        source=work/'verify.swift'
        source.write_text(''.join((ROOT/'ios/App'/name).read_text() for name in
                                 ['NativeSprintController.swift','NativeSwimController.swift'])+SWIFT)
        subprocess.run(['swift','-module-cache-path',str(work/'modules'),str(source),str(fixture)],check=True)

if __name__=='__main__': main()
