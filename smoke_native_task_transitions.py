#!/usr/bin/env python3
"""Focused task/input/shot events using real local CLP1 animation tracks.

This verifies current native integration invariants, not a retail-game replay.
No Metal device, Simulator, copied game data or repository asset writes.
"""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parent
TEST=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
let definitions=try NativeFootWeaponAnimation.load(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/foot-animation.json")))
func animator(_ id:Int,twin:Bool=false)->NativeFootAnimation {
 let result=NativeFootAnimation(library:library,random:{0.37});var definition=definitions[id]!
 if twin{definition.twin=true};result.arm(definition);return result
}
func aim(_ result:NativeFootAnimation,frames:Int=90){
 var input=NativeFootAnimation.Input();input.gun = .init()
 for _ in 0..<frames{result.control(.init(aim:true,held:true));_ = result.update(delta:1/120,input:input)}
}
var checks=0
let twin=animator(22,twin:true);aim(twin)
var armed=NativeFootAnimation.Input();armed.gun = .init()
twin.control(.init(fire:true,aim:true,held:true));_ = twin.update(delta:1/120,input:armed)
twin.control(.init(fire:true,aim:true,held:true));let dual=twin.update(delta:0.2,input:armed)
precondition(dual.shots == [false,true] && dual.shot && !dual.shotLeft,"A dual-hand mask must emit two events and retain legacy booleans");checks += 1
let stream=animator(41);aim(stream)
stream.control(.init(fire:true,aim:true,held:true));_ = stream.update(delta:1/120,input:armed)
var ticks=0,burst=0
for _ in 0..<30{stream.control(.init(fire:true,aim:true,held:true));let frame=stream.update(delta:1/30,input:armed);ticks += frame.shots.count;burst=max(burst,frame.shots.count);precondition(frame.shots.allSatisfy{!$0});checks += 1}
precondition(ticks>=48 && ticks<=51 && burst>=2,"50Hz stream events may not collapse to display frames: \(ticks),burst\(burst)");checks += 1
for kind in 0..<3 {
 let gun=animator(22,twin:true)
 if kind==0{gun.control(.init(fire:true,held:true))}
 if kind==1{_ = gun.fire(held:true)}
 if kind==2{_ = gun.fire(held:false)}
 gun.cancelInput()
 for _ in 0..<120{precondition(gun.update(delta:1/120).shots.isEmpty,"Queued trigger survived cancellation");checks += 1}
}
let held=animator(22,twin:true);aim(held)
var fired=false
for _ in 0..<120 {
 held.control(.init(fire:true,aim:true,held:true));let frame=held.update(delta:1/120,input:armed)
 if !frame.shots.isEmpty{precondition(frame.shots==[false]);fired=true;break}
}
precondition(fired);held.cancelInput()
for _ in 0..<120{precondition(held.update(delta:1/120).shots.isEmpty,"Left-hand follow-up survived input cancel");checks += 1}
let task=animator(22),style=task.style.walk
_ = task.launch()
var airborne=NativeFootAnimation.Input();airborne.air="fall";airborne.fly = .init(state:13,pitch:0.6,roll:0.7);airborne.swim = .init(state:5,pitch:0.4);airborne.ratio=2;airborne.sprint=true
for i in 0..<120{airborne.position=SIMD3(0,Double(i*i)/2400,30);_ = task.update(delta:1/60,input:airborne)}
task.resetMovementTask();let clean=task.update(delta:1/60)
precondition(task.armedWith==22 && task.style.walk==style && !task.busy && !task.acting)
precondition(clean.figurePitch==0 && clean.figureRoll==0 && clean.legBend == .zero && clean.flight==nil && clean.shots.isEmpty)
precondition(!clean.blends.contains{$0.clip.contains("fall_") || $0.clip.contains("jump_") || $0.clip.hasPrefix("swim/") || $0.clip.hasPrefix("parachute/")});checks += 3
task.die("koFront");task.resetMovementTask();precondition(task.dead);task.revive();precondition(!task.dead);checks += 2
let flight=NativePersonalFlightController();flight.wear(true);flight.dive(velocity:SIMD3(3,-20,4),rising:-20,heading:2.4);flight.steer(x:1,y:1,open:true,up:true,down:true,stop:true);flight.stop()
precondition(flight.worn && !flight.on && !flight.lifts && flight.linearVelocity == .zero && flight.heading==2.4)
flight.dive(velocity:.zero,rising:-12,heading:2.4);_ = flight.step(delta:1/60);precondition(flight.state==1,"Stop left a queued canopy deployment");checks += 2
flight.stop();flight.takeOff(heading:1.2,velocity:SIMD3(3,2,4));let velocity=flight.linearVelocity
flight.steer(x:1,y:1,open:true,up:true,down:true,stop:true);flight.cancelInput()
precondition(flight.on && flight.flying && flight.worn && flight.heading==1.2 && flight.linearVelocity==velocity);checks += 1
let presentation=NativeFlightAnimation(duration:{library.duration(of:$0)})
var maxBend=0.0
for i in 0..<180{let frame=presentation.update(delta:1/60,input:.init(state:13),position:SIMD3(0,Double(i*i)/2400,30),heading:0);maxBend=max(maxBend,simd_length(frame.bend))}
precondition(maxBend>0.0001)
_ = presentation.update(delta:1/60,input:nil,position:SIMD3(0,14,30),heading:0)
let inactive=presentation.update(delta:1/60,input:nil,position:SIMD3(0,14,30),heading:0)
precondition(inactive.bend == .zero && inactive.jet==nil && !presentation.showing,"Inactive leg modifier remained latched")
presentation.reset();let restarted=presentation.update(delta:1/60,input:.init(state:12),position:SIMD3(1000,1000,1000),heading:0)
precondition(restarted.bend == .zero && restarted.velocity == .zero);checks += 3
print("PASS task transitions:",checks,"checks; dual events",dual.shots,"continuous1s",ticks,"maxburst",burst,"real animation clips",library.clipCount)
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-core-task-transitions-') as temporary:
  work=Path(temporary)
  skeletal=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text()
  library=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
  aim=skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]
  source=library+'\nfinal class NativeSkeletalActor {\n'+aim+'}\n'
  for name in ['NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePersonalFlightController']:
   source+='\n'+(ROOT/'ios/App'/f'{name}.swift').read_text()
  (work/'verify.swift').write_text(source+TEST)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'verify.swift'),str(ROOT)],check=True)
if __name__=='__main__':main()
