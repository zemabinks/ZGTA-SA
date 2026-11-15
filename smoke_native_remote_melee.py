#!/usr/bin/env python3
"""Replay the actual archived remote ground clause and native dispatch hookup.

This is visual strike inference, not damage targeting. No original code/data
or generated reference rows leave ignored local-only/.
"""
from pathlib import Path
import json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/remote-melee-context'
JS=r'''
const fs=require('node:fs'),assert=require('node:assert/strict');
const {archivedModules}=require(process.cwd()+'/smoke_vehicle_dynamics');
const load=archivedModules(),factory=load.factories[19737],source=factory.toString();
const begin=source.indexOf('$&&C.fire(!1,N.move>1?"run":'),end=source.indexOf(';let J=',begin);
assert(begin>=0&&end>begin,'Original remote fire clause boundary changed');
const clause=source.slice(begin,end),start=clause.indexOf('((e,t)=>')+1,brace=clause.indexOf('{',start);let depth=1,finish=brace+1;
for(;depth;finish++){if(clause[finish]==='{')depth++;else if(clause[finish]==='}')depth--}
const contextSource=clause.slice(start,finish);
const makeContext=factory.constructor('ng','tk','return ('+contextSource+')');
const makeDispatch=factory.constructor('ng','tk','return (e,N,pending)=>{const $=pending;let calls=0,aside=null;const C={fire:(_held,a)=>{calls++;aside=a}};'+clause+';return {calls,aside}}');
let seed=123456789;const random=()=>((seed=(Math.imul(seed,1664525)+1013904223)>>>0)/4294967296);
const cases=[];
function append(position,heading,target,mode,movement,pending,down=true,life=100){
 const attacker={group:{position:{x:position[0],z:-position[1]}},person:{},seen:{down:true,life:0}},same={id:'attacker',position,walking:true,down:true,life:0};
 const person={id:'body',position:target,walking:mode!=='vehicle',down,life};
 const own=mode==='own'||mode==='own-not-walking'?{...person,id:'own',walking:mode==='own'}:null;
 const people=mode==='self'?[same]:mode==='own'||mode==='own-not-walking'?[]:[same,person];
 const ng=own&&{walking:own.walking,down:own.down,life:own.life,x:target[0],y:target[1]},tk=new Map([['attacker',attacker]]);
 for(const p of people)if(p.id!=='attacker')tk.set(p.id,{person:p.walking?{}:null,seen:{down:p.down,life:p.life},group:{position:{x:p.position[0],z:-p.position[1]}}});
 const N={heading:-heading,move:movement},expected=makeContext(ng,tk)(attacker,N),dispatch=makeDispatch(ng,tk)(attacker,N,pending);
 cases.push({position,heading,own,people,movement,pending,expected,dispatch});
}
for(const distance of[0,.299999,.3,.300001,2.099999,2.1,2.100001])for(const angle of[0,Math.PI/3-1e-8,Math.PI/3+1e-8,Math.PI,-Math.PI/2])for(const heading of[0,.7,-2.1])for(const mode of['own','own-not-walking','peer','vehicle','self']){
 const offset=[Math.sin(heading+angle)*distance,Math.cos(heading+angle)*distance];
 append([10,-20,2],heading,[10+offset[0],-20+offset[1],10000],mode,distance>1?1.5:0,cases.length%3!==0);
}
for(let i=0;i<1800;i++){
 const p=[random()*30-15,random()*30-15,random()*2000],heading=random()*Math.PI*2-Math.PI,target=[p[0]+random()*6-3,p[1]+random()*6-3,p[2]+random()*1000-500],mode=['own','own-not-walking','peer','vehicle','self'][i%5];
 append(p,heading,target,mode,[0,1,1.000001,2][i%4],i%3!==0,i%4===0,i%4===1?0:100);
}
fs.writeFileSync(process.argv[2],JSON.stringify(cases));console.log('Actual browser remote context/fire clause:',cases.length,'cases');
'''
def declaration(source,token):
 start=source.index(token);brace=source.index('{',start);depth=1;end=brace+1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end]

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 remote=(ROOT/'ios/App/NativeRemoteFootAnimation.swift').read_text()
 begin=renderer.index('                    let groundContext=NativeRemoteMeleeContext.');end=renderer.index('                    let state=NativeRemoteFootAnimation.Snapshot',begin)
 integration=renderer[begin:end]
 assert 'nearFlooredTarget:groundContext' in renderer[end:renderer.index('                    let frame=',end)]
 dispatch=remote[remote.index('        let latest ='):remote.index('        if state.airborne {')]
 source='import Foundation\nimport simd\n'+(ROOT/'ios/App/NativeRemoteMeleeContext.swift').read_text()+r'''
struct Person:Decodable {var id:String;var position:[Double];var walking:Bool;var down:Bool;var life:Double
 var context:NativeRemoteMeleeContext.Person{.init(id:id,position:SIMD3(position[0],position[1],position[2]),walking:walking,down:down,life:life)}}
struct Dispatch:Decodable {var calls:Int;var aside:String?}
struct Row:Decodable {var position:[Double];var heading:Double;var own:Person?;var people:[Person];var movement:Double;var pending:Bool;var expected:Bool;var dispatch:Dispatch}
struct State {var latestShots:Int?=2;var shots=2;var movement:Double;var nearFlooredTarget:Bool}
final class SpyAnimator {var calls=0;var aside:String?;func fire(held:Bool,aside:String?)->Bool{precondition(!held);calls+=1;self.aside=aside;return true}}
func dispatch(state:State)->(Int,String?) {var fired:Int?=1;let animator=SpyAnimator()
'''+dispatch+r'''
 return(animator.calls,animator.aside)
}
struct Remote {var id:String;var position:SIMD3<Float>;var heading:Float=0;var vehicleID:String?;var ridingVehicleID:String?;var code="s7";var down=0;var life=100}
struct Foot {var floored=false}
struct RendererInput {
 var player=Remote(id:"attacker",position:.zero),remotePlayers:[Remote]=[]
 var camera=SIMD3<Float>(30,30,0),driving=false,footAnimator:Foot?=Foot(),health=100
 func context()->Bool {
'''+integration+r'''
 return groundContext
 }
}
let rows=try JSONDecoder().decode([Row].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
var checks=0,positive=0,ground=0,running=0,misses=0
func check(_ value:Bool,_ message:String){precondition(value,message);checks+=1}
for row in rows {
 let position=SIMD3(row.position[0],row.position[1],row.position[2])
 let actual=NativeRemoteMeleeContext.nearFlooredTarget(attackerID:"attacker",position:position,heading:row.heading,own:row.own?.context,people:row.people.map(\.context))
 check(actual==row.expected,"Original browser context differs")
 var state=State(movement:row.movement,nearFlooredTarget:actual);state.shots=row.pending ? 2:1;state.latestShots=state.shots
 let event=dispatch(state:state);check(event.0==row.dispatch.calls&&event.1==row.dispatch.aside,"Actual native fire dispatch differs from original clause")
 if actual{positive+=1};if event.1=="ground"{ground+=1};if event.1=="run"{running+=1};if event.0==0{misses+=1}
}
var input=RendererInput()
input.remotePlayers=[.init(id:"attacker",position:.zero,down:1),.init(id:"body",position:SIMD3(0,1,10000),down:1)]
check(input.context(),"Actual renderer passes other floored foot actors, ignoring height")
input.remotePlayers[1].ridingVehicleID="car";check(!input.context(),"Passenger excluded from foot context")
input.remotePlayers[1].ridingVehicleID=nil;input.remotePlayers[1].vehicleID="car";check(!input.context(),"Driver excluded from foot context")
input.remotePlayers[1].vehicleID=nil;input.remotePlayers[1].code="410";check(!input.context(),"Vehicle model excluded from foot context")
input.remotePlayers=[];input.camera=SIMD3(0,1,-10000);input.footAnimator=Foot(floored:true)
check(input.context(),"Actual renderer includes own floored pedestrian")
input.driving=true;check(!input.context(),"Own driving actor excluded")
input.driving=false;input.footAnimator=Foot();input.health=0;check(input.context(),"Own dead pedestrian included")
input.health=100;check(!input.context(),"Own healthy standing pedestrian ignored")
check(positive>100&&ground>20&&running>100&&misses>100,"Exercise active/neutral and ground/run dispatch")
let report:[String:Any]=["pass":true,"cases":rows.count,"checks":checks,"positiveContexts":positive,"groundDispatches":ground,"runDispatches":running,"noMarkerDispatches":misses,"authority":"Actual archived remote fire clause + native context/actual extracted Renderer and RemoteFoot dispatch; visual only, no retail runtime or damage policy claim"]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("PASS original remote melee context: \(rows.count) cases, \(checks) context/dispatch/Renderer checks")
'''
 with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temporary:
  work=Path(temporary);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(OUT/'reference.json')],cwd=ROOT,check=True)
  (work/'main.swift').write_text(source)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify'),str(OUT/'reference.json'),str(OUT/'report.json')],check=True)
if __name__=='__main__':main()
