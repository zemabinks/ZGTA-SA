#!/usr/bin/env python3
"""Compare held gun animation state to the unmodified public R6 tM closure."""
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(process.argv[2],'utf8'),start=source.indexOf('tM=function(){let t={there:'),end=source.indexOf('}(),tk=null',start);
if(start<0||end<0)throw Error('Original R6 gun state machine unavailable');
const make=()=>vm.runInNewContext('('+source.slice(start+3,end+1)+')()',{h:{NONE:0,AIM:1,FIRE:2,END_LEISURE:6,END_NOW:7},d:{RZ:.02}});
const definitions=JSON.parse(fs.readFileSync(process.argv[3],'utf8')).weapons, cases=[];
for(const id of [22,24,25,26,28,30,34,35,37,41,42])for(const crouched of [false,true]){
 const def=definitions.find(x=>x.id===id),state=make(),length=id===37||id===41||id===42?1.6:id===35?1.4:1.2;
 const config={loop:crouched?def.crouched:def.loop,length,breakout:def.breakout??Infinity,twin:def.twin,continuous:def.continuous??false,crouched};
 for(let frame=0;frame<700;frame++){
  const delta=[1/60,1/50,1/75,.05][frame%4],control={aim:frame<130||frame>=430&&frame<470,fire:frame>=50&&frame<270||frame>=330&&frame<410||frame>=520&&frame<580,held:frame<290||frame>=330&&frame<470||frame>=520&&frame<580,pushed:frame===280||frame>=470&&frame<480,ready:!(frame>=170&&frame<220)};
  state.control(control);let method=null;if(frame===145){state.cancel(config);method='cancel'}if(frame===380){state.shoot(config);method='shoot'}if(frame===490){state.drop();method='drop'}
  const shots=state.step(delta,config),expected={shots,on:state.on,blend:state.blend,time:state.at,firing:state.firing,fired:state.fired,shooting:state.shooting,ended:state.ended};
  cases.push({id,crouched,frame,delta,control,config:{...config,breakout:Number.isFinite(config.breakout)?config.breakout:null},method,expected});
 }
}
fs.writeFileSync(process.argv[4],JSON.stringify(cases));
'''
SWIFT=r'''
private enum ExactFixtureJSON: Decodable {
 case object([String:ExactFixtureJSON]),array([ExactFixtureJSON]),number(Double),bool(Bool),string(String),null
 init(from decoder:Decoder)throws {
  let c=try decoder.singleValueContainer()
  if c.decodeNil(){self = .null}
  else if let x=try? c.decode(Bool.self){self = .bool(x)}
  else if let x=try? c.decode(Double.self){self = .number(x)}
  else if let x=try? c.decode(String.self){self = .string(x)}
  else if let x=try? c.decode([ExactFixtureJSON].self){self = .array(x)}
  else{self = .object(try c.decode([String:ExactFixtureJSON].self))}
 }
 var any:Any { switch self {case .object(let x):return x.mapValues{ $0.any };case .array(let x):return x.map{ $0.any };case .number(let x):return NSNumber(value:x);case .bool(let x):return x;case .string(let x):return x;case .null:return NSNull()} }
}

let rows=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [[String:Any]]
var current="",state=NativeGunAnimation(),comparisons=0
func num(_ d:[String:Any],_ k:String)->Double{(d[k] as! NSNumber).doubleValue}
for row in rows{
 let key="\(row["id"]!)-\(row["crouched"]!)",frame=row["frame"] as! Int
 if key != current{current=key;state=NativeGunAnimation()}
 let c=row["config"] as! [String:Any],l=c["loop"] as! [String:Any],b=row["control"] as! [String:Bool],expected=row["expected"] as! [String:Any]
 let config=NativeGunAnimation.Configuration(loop:NativeFootWeaponAnimation.Loop(start:num(l,"start"),end:num(l,"end"),fire:num(l,"fire"),every:(l["every"] as? NSNumber)?.doubleValue),length:num(c,"length"),breakout:(c["breakout"] as? NSNumber)?.doubleValue ?? .infinity,twin:c["twin"] as! Bool,continuous:c["continuous"] as! Bool,crouched:c["crouched"] as! Bool)
 state.control(fire:b["fire"]!,aim:b["aim"]!,held:b["held"]!,pushed:b["pushed"]!,ready:b["ready"]!)
 if let method=row["method"] as? String{if method=="cancel"{state.cancel(config)}else if method=="shoot"{state.shoot(config)}else{state.drop()}}
 let shots=state.step(delta:num(row,"delta"),configuration:config)
 assert(shots==expected["shots"] as! Int,"\(key):\(frame) shots \(shots) != \(expected["shots"]!)")
 assert(abs(state.time-num(expected,"time"))<0.000000001,"\(key):\(frame) time")
 assert(abs(state.blend-num(expected,"blend"))<0.000000001,"\(key):\(frame) blend")
 for(k,v)in[("on",state.on),("firing",state.firing),("fired",state.fired),("shooting",state.shooting),("ended",state.ended)]{assert(v==expected[k] as! Bool,"\(key):\(frame) \(k)");comparisons+=1}
 comparisons+=3
}
print("PASS: \(rows.count) archived-browser tM gun animation frames, \(comparisons) comparisons: aim/fire/cancel/restart, continuous streams, twin shots, not-ready pause and breakout")
'''
def main():
    source=next(path for path in (ROOT/'local-only/site/_next/static/chunks').glob('*.js') if 'tM=function(){let t={there:' in path.read_text())
    data=ROOT/'local-only/site/game/native/foot-animation.json'
    if not data.exists():subprocess.run(['node',str(ROOT/'prepare_native_foot_animation.js')],cwd=ROOT,check=True)
    with tempfile.TemporaryDirectory(prefix='zgta-gun-animation-') as tmp:
        work=Path(tmp);(work/'reference.js').write_text(JS)
        subprocess.run(['node',str(work/'reference.js'),str(source),str(data),str(work/'reference.json')],check=True)
        (work/'verify.swift').write_text((ROOT/'ios/App/NativeGunAnimation.swift').read_text()+SWIFT)
        subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
