#!/usr/bin/env python3
"""Compare actual publiccv contact/water sound events with the native mixer."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),load=require(process.cwd()+'/smoke_vehicle_dynamics').archivedModules(),s=load.factories[19737].toString(),T=load(85339);
const a=s.indexOf('cv=function(e){'),b=s.indexOf('(()=>sv.current',a),c=s.indexOf('kO={'),d=s.indexOf(';var kK=',c);
if([a,b,c,d].some(i=>i<0))throw Error('Original cv boundary changed');
let seed=913,random=[],events=[],delay=0;
const math=Object.create(Math);math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;let v=seed/4294967296;random.push(v);return v};
const event=(kind,id,sample,p={})=>events.push({kind,id,sample,at:p.at?[p.at.x,p.at.y,p.at.z]:null,rate:p.rate??1,gain:p.volume??1,start:p.start??0,near:p.near??0,reach:p.reach??0,delay});
const voice={once:(sample,p)=>event('once','',sample,p),hold:(id,sample,p)=>event('hold',id,sample,p),drop:id=>event('drop',id,''),to:()=>voice};
const context=vm.createContext({Math:math,n0:load(77287),lq:{WA:1},setTimeout:(callback,ms)=>{delay=ms/1000;callback();delay=0}});
vm.runInContext('let '+s.slice(c,d)+';globalThis.create='+s.slice(a+3,b),context);
const original=context.create(()=>voice),rows=[],wakers=Array.from({length:5},()=>({}));
const run=(input,fn)=>{events=[];random=[];fn();rows.push({input,random:[...random],events})};
for(let i=0;i<9500;i++){
 const at=[Math.sin(i*.013)*20,2+i%3,Math.cos(i*.017)*20],position=new T.Pq0(...at),delta=[1/120,1/60,1/30,.08,.11,.2][i%6];
 if(i%1000<800){
  const input={kind:'crash',id:'object-'+i%13,at,mine:[0,63,67,62,17,178,-1,999][i%8],other:[0,63,67,62,34,178,100,999][Math.floor(i/9)%8],impact:[0,.00001,.0001,.01,.1,.25,1,4,-1][i%9],slide:[0,.001,.05,.3,1,10][i%6]};
  run(input,()=>original.crash(input.id,{at:position,mine:input.mine,other:input.other,impact:input.impact,slide:input.slide}));
 }
 if(i%97<4){
  const type=['fell','dove','stroke','wake'][i%97],object=wakers[Math.floor(i/97)%5],input={kind:type,at,speed:(i%140)-20,id:'water'};
  run(input,()=>{if(type==='fell')original.wet.fell('water',position,input.speed);else if(type==='wake'){original.wet.wake(object,position);input.id=object.wetHeard}else original.wet[type]('water',position)});
 }
 run({kind:'update',delta},()=>original.update(delta));
 if(i%997===996)run({kind:'quiet'},()=>original.quiet());
}
const config=JSON.parse(fs.readFileSync('local-only/site/game/native/contact-audio.json'));fs.writeFileSync(process.argv[2],JSON.stringify({config,rows}));
'''
SWIFT=r'''
let document=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
let configuration=try JSONDecoder().decode(NativeContactAudio.Configuration.self,from:JSONSerialization.data(withJSONObject:document["config"]!))
let audio=NativeContactAudio(configuration:configuration)
var count=0,maximum=0.0
func n(_ row:[String:Any],_ key:String)->Double {(row[key] as! NSNumber).doubleValue}
func v(_ row:[String:Any])->SIMD3<Double> {let a=row["at"] as! [Double];return SIMD3(a[0],a[1],a[2])}
func check(_ actual:Double,_ expected:Double,_ label:String){count += 1;maximum=max(maximum,abs(actual-expected));precondition(abs(actual-expected)<2e-11,"\(label): \(actual) != \(expected)")}
for (index,row) in (document["rows"] as! [[String:Any]]).enumerated(){
 let input=row["input"] as! [String:Any],kind=input["kind"] as! String,random=row["random"] as! [Double];var cursor=0
 func rng()->Double{precondition(cursor<random.count,"extra RNG at \(index)");defer{cursor += 1};return random[cursor]}
 let result:[NativeContactAudio.Event]
 switch kind {
 case "crash":result=audio.crash(id:input["id"] as! String,impact:n(input,"impact"),position:v(input),mine:input["mine"] as? Int,other:input["other"] as? Int,slide:n(input,"slide"),random:rng)
 case "fell":result=audio.fell(id:"water",position:v(input),speed:n(input,"speed"))
 case "dove","stroke":result=[audio.waterStroke(id:"water",position:v(input),dive:kind=="dove",random:rng())]
 case "wake":audio.wake(id:input["id"] as! String,position:v(input));result=[]
 case "update":result=audio.update(delta:n(input,"delta"))
 case "quiet":result=audio.quiet()
 default:fatalError("Unknown fixture")
 }
 precondition(cursor==random.count,"unused RNG \(index)")
 let expected=row["events"] as! [[String:Any]]
 precondition(result.count==expected.count,"event count \(index)/\(kind): \(result.count) != \(expected.count)")
 for (actual,other) in zip(result,expected){
  precondition(actual.kind==other["kind"] as! String,"kind \(index)")
  if actual.kind != "once" {precondition(actual.id==other["id"] as! String,"id \(index)")}
  if actual.kind=="drop" {continue}
  precondition(actual.sample==other["sample"] as! String,"sample \(index)")
  for (name,value) in [("rate",actual.rate),("gain",actual.gain),("start",actual.start),("delay",actual.delay),("near",actual.near),("reach",actual.reach)]{check(value,n(other,name),"\(index)/\(name)")}
  let point=v(other);for component in 0..<3{check(actual.position[component],point[component],"\(index)/position")}
 }
}
print("PASS: \((document["rows"] as! [Any]).count) original material-impact/scrape/water mixer operations, \(count) event comparisons, maximum error \(maximum)")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-contact-audio-')as directory:
  work=Path(directory);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'fixture.json')],cwd=ROOT,check=True)
  source=ROOT/'ios/App/NativeContactAudio.swift'
  if not source.exists():source=ROOT/'local-only/research/NativeContactAudio.swift'
  (work/'verify.swift').write_text(source.read_text()+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'fixture.json')],check=True)
if __name__=='__main__':main()
