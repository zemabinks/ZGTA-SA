#!/usr/bin/env python3
"""Replay actual54205 parachute/jetpack movement against its native port."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
from tests.movement.smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),load=require(process.cwd()+'/smoke_vehicle_dynamics').archivedModules(),api=load(54205),T=load(85339);
const vector=a=>new T.Pq0(...a),array=v=>[v.x,v.y,v.z],cases=[];
for(const kind of ['bare','open','late_open','ground_open','float','fall_fast','jet_ground','jet_air','jet_ceiling','jet_brake','jet_toggle','jet_ground_down']){
 const controller=api.$l(),jet=kind.startsWith('jet'),frames=[],initial={jet,velocity:[3,jet?2:0,-4],rise:kind==='fall_fast'?-34:-12,heading:2.8};
 if(jet){controller.wear(true);controller.takeOff(initial.heading,vector(initial.velocity))}else controller.dive(vector(initial.velocity),initial.rise,initial.heading);
 for(let i=0;i<1400;i++){
  const delta=[1/60,1/30,1/120,1/50][i%4];
  const input={x:Math.sin(i*.037),y:Math.cos(i*.021),open:!jet&&['open','late_open','ground_open','float'].includes(kind)&&i===(kind==='late_open'?350:kind==='ground_open'?0:20),up:jet&&i%180<120,down:jet&&i%180>=160,stop:kind==='jet_brake'&&i%150>60};
  if(kind==='bare'||kind==='ground_open'){input.x=0;input.y=0}
  const grounded=jet?(kind==='jet_ground_down'||kind==='jet_ground'&&i<40||i>1280):kind==='ground_open'?i<4||i>450:i>(kind==='fall_fast'?80:1150);
  const heading=kind==='jet_toggle'?Math.sin(i*.01)*9:2.8+Math.sin(i*.023)*3,height=kind==='jet_ceiling'?80+i*.2:i%7===0?null:30+Math.cos(i*.03)*20;
  const wear=kind==='jet_toggle'&&[300,500,700,900].includes(i)?i%400===100:null;
  if(wear!==null)controller.wear(wear);
  const takeOff=kind==='jet_toggle'&&[501,901].includes(i);if(takeOff)controller.takeOff(heading);
  const stop=kind==='jet_toggle'&&i===1100;if(stop)controller.stop();
  controller.steer(input);const canLift=controller.lifts(),canDive=controller.dives(-10-i%8,height);
  const result=controller.step(delta,{grounded,heading,height}),velocity=controller.velocity(new T.Pq0());
  frames.push({input,delta,grounded,heading,height,wear,takeOff,stop,canLift,canDive,
   result:result?{move:array(result.move),rise:result.rise,landed:result.landed}:null,
   state:{on:controller.on,chuting:controller.chuting,state:controller.state,pitch:controller.pitch,roll:controller.roll,heading:controller.heading,worn:controller.worn,flying:controller.flying,velocity:array(velocity)}});
 }
 cases.push({kind,initial,frames});
}
fs.writeFileSync(process.argv[2],JSON.stringify(cases));
'''
SWIFT=r'''
let cases=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [[String:Any]]
func number(_ row:[String:Any],_ key:String)->Double {(row[key] as! NSNumber).doubleValue}
func flag(_ row:[String:Any],_ key:String)->Bool {row[key] as! Bool}
func vector(_ raw:Any)->SIMD3<Double> {let a=raw as! [NSNumber];return SIMD3(a[0].doubleValue,a[1].doubleValue,a[2].doubleValue)}
var comparisons=0,frames=0,maximum=0.0
func check(_ actual:Double,_ expected:Double,_ label:String){comparisons += 1;maximum=max(maximum,abs(actual-expected));precondition(actual.isFinite && abs(actual-expected)<2e-10,"\(label): \(actual) != \(expected)")}
func checkVector(_ actual:SIMD3<Double>,_ raw:Any,_ label:String){let expected=vector(raw);for i in 0..<3{check(actual[i],expected[i],label)}}
for test in cases {
 let controller=NativePersonalFlightController(),initial=test["initial"] as! [String:Any]
 if flag(initial,"jet"){controller.wear(true);controller.takeOff(heading:number(initial,"heading"),velocity:vector(initial["velocity"]!))}
 else{controller.dive(velocity:vector(initial["velocity"]!),rising:number(initial,"rise"),heading:number(initial,"heading"))}
 for (index,row) in (test["frames"] as! [[String:Any]]).enumerated(){
  let input=row["input"] as! [String:Any],label="\(test["kind"]!)/\(index)"
  if let worn=row["wear"] as? Bool{controller.wear(worn)}
  if flag(row,"takeOff"){controller.takeOff(heading:number(row,"heading"))}
  if flag(row,"stop"){controller.stop()}
  controller.steer(x:number(input,"x"),y:number(input,"y"),open:flag(input,"open"),up:flag(input,"up"),down:flag(input,"down"),stop:flag(input,"stop"))
  precondition(controller.lifts==flag(row,"canLift"),label+" lift")
  let height=(row["height"] as? NSNumber)?.doubleValue
  precondition(controller.dives(rising:Double(-10-index%8),height:height)==flag(row,"canDive"),label+" dive")
  let output=controller.step(delta:number(row,"delta"),grounded:flag(row,"grounded"),heading:number(row,"heading"),height:height)
  if let expected=row["result"] as? [String:Any]{
   precondition(output != nil,label+" missing output");checkVector(output!.move,expected["move"]!,label+" move");check(output!.rise,number(expected,"rise"),label+" rise")
   if let landing=expected["landed"] as? [String:Any]{precondition(output!.landed != nil,label+" missing landing");check(output!.landed!.speed,number(landing,"speed"),label+" landing speed");precondition(output!.landed!.canopy==flag(landing,"canopy") && output!.landed!.dead==flag(landing,"dead"),label+" landing flags")}
   else{precondition(output!.landed==nil,label+" unexpected landing")}
  }else{precondition(output==nil,label+" unexpected output")}
  let state=row["state"] as! [String:Any]
  precondition(controller.on==flag(state,"on") && controller.chuting==flag(state,"chuting") && controller.worn==flag(state,"worn") && controller.flying==flag(state,"flying") && controller.state==Int(number(state,"state")),label+" flags")
  check(controller.pitch,number(state,"pitch"),label+" pitch");check(controller.roll,number(state,"roll"),label+" roll");check(controller.heading,number(state,"heading"),label+" heading")
  checkVector(controller.linearVelocity,state["velocity"]!,label+" velocity");frames += 1
 }
}
print("PASS: \(frames) archived-browser parachute/jetpack frames, \(comparisons) movement/state/landing checks; maximum error \(maximum)")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-personal-flight-')as directory:
  work=Path(directory);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'fixture.json')],cwd=ROOT,check=True)
  helper=FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]
  (work/'verify.swift').write_text((ROOT/'ios/App/NativePersonalFlightController.swift').read_text()+helper+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'fixture.json')],check=True)
if __name__=='__main__':main()
