#!/usr/bin/env python3
"""Compare damage, doors, state packets and blast impulses to archived module66242."""
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),{archivedModules}=require(process.argv[2]+'/smoke_vehicle_dynamics'),load=archivedModules(),T=load(85339);
let used=[],seed=83720;const math=Object.create(Math);math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;const value=seed/4294967296;used.push(value);return value};
const context=vm.createContext({Math:math}),factory=vm.runInContext('('+load.factories[66242].toString()+')',context),carrier={exports:{}};factory(carrier,carrier.exports,load);const api=carrier.exports;
const vec=v=>new T.Pq0(...v),array=v=>v?[v.x,v.y,v.z]:null;
function body(i){const yaw=i*.017,pitch=.4*Math.sin(i*.013),up=i>=260&&i<900?-1:1;
 const right=[Math.cos(yaw),0,Math.sin(yaw)],forward=[Math.sin(yaw)*Math.cos(pitch),Math.sin(pitch),-Math.cos(yaw)*Math.cos(pitch)],vertical=[-Math.sin(yaw)*Math.sin(pitch)*up,Math.cos(pitch)*up,Math.cos(yaw)*Math.sin(pitch)*up];
 return{position:[1+i*.013,2,3],right,forward,up:vertical,move:i>=260&&i<900?[0,0,0]:[.6*Math.sin(i*.11),.02,.3*Math.cos(i*.023)],turn:[.05*Math.sin(i*.03),.02,.04*Math.cos(i*.07)]}}
function nativeBody(input){return Object.fromEntries(Object.entries(input).map(([key,value])=>[key,vec(value)]))}
function state(d){return {health:d.health,wrecked:d.wrecked,burning:d.burning,godly:d.godly,intensity:d.intensity,looks:Array.from({length:11},(_,i)=>d.look(i)),lights:[...d.lights],wheels:[...d.wheels],open:Array.from({length:11},(_,i)=>d.isOpen(i)),doors:Array.from({length:6},(_,i)=>{const x=d.door(i);return{open:x.open,closed:x.closed,direction:x.dirn,axis:x.axis,angle:x.angle,previousAngle:x.prevAngle,angularVelocity:x.angVel,state:x.state}}),text:d.toText(),events:d.events.map(e=>({...e,...(e.point?{point:array(e.point)}:{})}))}}
const cases=[];
for(const [name,flags,model] of [['stock',0,420],['van',1,482],['bus',2,431],['reverse-bonnet',16,420],['hanging-boot',32,420],['tailgate',64,420],['fixed-boot',128,420],['no-doors',256,424],['hunter',256,425],['shamal',0,519],['nevada',0,553],['hydra',0,520]]){
 const config={mass:name==='bus'?5500:1400,collisionDamage:.65,maxX:1.05,flags,model},d=api._E(config,{maxX:config.maxX},flags,model),frames=[];
 for(let i=0;i<1120;i++){
  used=[];const b=body(i),actions=[];
  if(i%97===2)actions.push({kind:'loose',door:(Math.floor(i/97)%6),angle:(i%2?1:-1)*.7});
  if(i===180||i===950)actions.push({kind:'fix'});
  if(i===190)actions.push({kind:'load',health:974.5,text:'3434012122110101201'});
  if(i===930)actions.push({kind:'load',health:170,text:'this is not damage'});
  if(i===995)actions.push({kind:'inflict',amount:150});
  if(i===1040)actions.push({kind:'godly',value:true});
  if(i===1041)actions.push({kind:'inflict',amount:500});
  if(i===1050)actions.push({kind:'godly',value:false});
  if(i===1060)actions.push({kind:'blow'});
  if(i%53===0)actions.push({kind:'burst',wheel:Math.floor(i/53)%4});
  const nb=nativeBody(b);
  if(i<170||i>=960&&i<990){const piece=[1,2,3,4,5,6,7,8,9,10,19,0][i%12],force=i%17===0?3800:25+(i%7)*73,point=[b.position[0]+(i%3-1)*.9,2,3],normal=i%13===0?b.up:[-1,0,0];actions.push({kind:'record',intensity:force,piece,point,normal,building:i%11===0,rhino:i%23===0},{kind:'record',intensity:force*.5,piece:2,point:null,normal:null,building:false})}
  for(const a of actions){if(a.kind==='loose')d.letGo(a.door,a.angle);else if(a.kind==='fix')d.fix();else if(a.kind==='load')d.load(a.health,a.text);else if(a.kind==='inflict')d.inflict(a.amount);else if(a.kind==='godly')d.godly=a.value;else if(a.kind==='burst')d.burst(a.wheel);else if(a.kind==='blow')d.blowUp();else d.record(a.intensity,a.piece,a.point&&vec(a.point),a.normal&&vec(a.normal),a.building,a.rhino)}
  const previous={move:[.3*Math.sin(i*.11),0,.2*Math.cos(i*.023)],turn:[.01,0,.01]},current={move:b.move,turn:b.turn},hinges=Array.from({length:6},(_,j)=>j===4&&i%7===0?null:[(j%2?1:-1)*1.1,.2,-1+j*.6]);
  const impact=d.intensity,ticks=i%31===0?1.4:50/60;
  d.process(nb,ticks);d.swing(nb,nativeBody(previous),nativeBody(current),j=>hinges[j]&&vec(hinges[j]),ticks,impact);
  frames.push({body:b,previous,current,hinges,ticks,actions,random:[...used],expected:state(d)});d.events.length=0;
 }
 cases.push({name,config,frames});
}
const blasts=[];for(let i=0;i<1200;i++){const b=body(i),minimum=[-1,-2,-.5],maximum=[1,2,1.2],mass=500+(i%13)*300,centre=[b.position[0]+(i%27-13)*.7,2+(i%11-5)*.5,3+(i%17-8)*.65],subdued=i%3===0,radius=i%2?9:5,visible=i%2?300:150;const output=api.xM({...nativeBody(b),mass,bounds:{min:minimum,max:maximum}},vec(centre),subdued,{radius,visible});blasts.push({body:b,minimum,maximum,mass,centre,subdued,radius,visible,expected:output?{damage:output.damage,force:array(output.force),point:array(output.point)}:null})}
const texts=['0000000000000000000','4444444444444444444','0123401234012340123','000000000000000000','00000000000000000000','0000000000000000005','abc',''];
fs.writeFileSync(process.argv[3],JSON.stringify({cases,blasts,decodes:texts.map(text=>({text,expected:api.Ly(text)}))}));
'''
SWIFT=r'''
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
typealias D=NativeVehicleDamage
func vector(_ value:Any)->D.V {let a=value as! [Double];return .init(a[0],a[1],a[2])}
func body(_ row:[String:Any])->D.Body{.init(position:vector(row["position"]!),right:vector(row["right"]!),forward:vector(row["forward"]!),up:vector(row["up"]!),move:vector(row["move"]!),turn:vector(row["turn"]!))}
func velocity(_ row:[String:Any])->D.Velocity{.init(move:vector(row["move"]!),turn:vector(row["turn"]!))}
func array(_ value:D.V?)->Any{value.map{[$0.x,$0.y,$0.z]} ?? NSNull()}
func state(_ d:D)->[String:Any]{
 let doors:[[String:Any]]=d.doors.map{["open":$0.open,"closed":$0.closed,"direction":$0.direction,"axis":$0.axis,"angle":$0.angle,"previousAngle":$0.previousAngle,"angularVelocity":$0.angularVelocity,"state":$0.state]}
 let events:[[String:Any]]=d.events.map{e in var r:[String:Any]=["type":e.type];if let p=e.part{r["part"]=p};if let k=e.kind{r["kind"]=k};if let t=e.torn{r["torn"]=t};if let p=e.point{r["point"]=array(p)};if let f=e.force{r["force"]=f};return r}
 return ["health":d.health,"wrecked":d.wrecked,"burning":d.burning,"godly":d.godly,"intensity":d.intensity,"looks":d.looks,"lights":d.lights,"wheels":d.wheels,"open":(0..<11).map{d.isOpen($0)},"doors":doors,"text":d.text(),"events":events]
}
var comparisons=0,maximum=0.0
func check(_ actual:Any,_ expected:Any,_ label:String){
 comparisons += 1
 if expected is NSNull {precondition(actual is NSNull,label+" expected null");return}
 if let e=expected as? [String:Any]{guard let a=actual as? [String:Any]else{fatalError(label+" expected dictionary")};precondition(Set(a.keys)==Set(e.keys),label+" keys");for key in e.keys{check(a[key]!,e[key]!,label+"."+key)};return}
 if let e=expected as? [Any]{guard let a=actual as? [Any]else{fatalError(label+" expected array")};precondition(a.count==e.count,label+" count");for i in e.indices{check(a[i],e[i],label+"[\(i)]")};return}
 if let e=expected as? String{precondition(actual as? String==e,label+" text \(actual) != \(e)");return}
 let e=(expected as! NSNumber).doubleValue,a=(actual as! NSNumber).doubleValue,error=abs(a-e);maximum=max(maximum,error);precondition(error<1e-10,label+" \(a) != \(e)")
}
var frames=0
for item in fixture["cases"] as! [[String:Any]]{
 let config=item["config"] as! [String:Any],d=D(mass:config["mass"] as! Double,collisionDamage:config["collisionDamage"] as! Double,maxX:config["maxX"] as! Double,flags:config["flags"] as! Int,model:config["model"] as! Int)
 for (index,frame) in (item["frames"] as! [[String:Any]]).enumerated(){
  let random=frame["random"] as! [Double];var cursor=0
  func rng()->Double{precondition(cursor<random.count,"extra RNG");defer{cursor += 1};return random[cursor]}
  for a in frame["actions"] as! [[String:Any]]{switch a["kind"] as! String{
   case "loose":d.letGo(a["door"] as! Int,angle:a["angle"] as! Double)
   case "fix":d.fix()
   case "load":d.load(health:a["health"] as! Double,text:a["text"] as! String)
   case "inflict":d.inflict(a["amount"] as! Double)
   case "godly":d.godly=a["value"] as! Bool
   case "burst":d.burst(a["wheel"] as! Int)
   case "blow":d.blowUp(random:rng)
   default:d.record(intensity:a["intensity"] as! Double,piece:a["piece"] as! Int,point:a["point"] is NSNull ? nil:vector(a["point"]!),normal:a["normal"] is NSNull ? nil:vector(a["normal"]!),building:a["building"] as! Bool,rhino:a["rhino"] as? Bool ?? false)
  }}
  let b=body(frame["body"] as! [String:Any]),ticks=frame["ticks"] as! Double,impact=d.intensity,hinges=frame["hinges"] as! [Any]
  d.process(body:b,ticks:ticks,random:rng)
  d.swing(body:b,previous:velocity(frame["previous"] as! [String:Any]),current:velocity(frame["current"] as! [String:Any]),hinge:{hinges[$0] is NSNull ? nil:vector(hinges[$0])},ticks:ticks,intensity:impact,random:rng)
  precondition(cursor==random.count,"unused RNG")
  check(state(d),frame["expected"]!,"\(item["name"]!) frame\(index)");d.events.removeAll();frames += 1
 }
}
for (index,row) in (fixture["blasts"] as! [[String:Any]]).enumerated(){let output=D.explosion(body:body(row["body"] as! [String:Any]),minimum:vector(row["minimum"]!),maximum:vector(row["maximum"]!),mass:row["mass"] as! Double,centre:vector(row["centre"]!),subdued:row["subdued"] as! Bool,radius:row["radius"] as! Double,visible:row["visible"] as! Double);check(output.map{["damage":$0.damage,"force":array($0.force),"point":array($0.point)] as [String:Any]} ?? NSNull(),row["expected"]!,"blast\(index)")}
for row in fixture["decodes"] as! [[String:Any]]{let decoded=D.decode(row["text"] as! String);check(decoded.map{["looks":$0.looks,"open":$0.open,"lights":$0.lights,"wheels":$0.wheels] as [String:Any]} ?? NSNull(),row["expected"]!,"decode")}
print("PASS original vehicle damage: \(frames) frames, 1200 blasts, \(comparisons) comparisons, maximum error \(maximum)")
'''
def main():
    with tempfile.TemporaryDirectory(prefix='zgtasa-damage-') as directory:
        folder=Path(directory);(folder/'fixture.js').write_text(JS)
        subprocess.run(['node',str(folder/'fixture.js'),str(ROOT),str(folder/'fixture.json')],check=True)
        source=ROOT/'ios/App/NativeVehicleDamage.swift'
        if not source.exists():source=ROOT/'local-only/research/NativeVehicleDamage.swift'
        (folder/'main.swift').write_text(source.read_text()+'\n'+SWIFT)
        subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-damage-module-cache',str(folder/'main.swift'),'-o',str(folder/'check')],check=True)
        subprocess.run([str(folder/'check'),str(folder/'fixture.json')],check=True)
if __name__=='__main__':main()
