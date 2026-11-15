#!/usr/bin/env python3
"""Compare native follow cameras against the actual archived client functions."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),source=fs.readFileSync(process.argv[2],'utf8'),archive=fs.readFileSync(process.argv[3],'utf8'),meta=JSON.parse(fs.readFileSync(process.argv[4],'utf8'));
class V{
 constructor(x=0,y=0,z=0){this.set(x,y,z)}set(x,y,z){Object.assign(this,{x,y,z});return this}setY(y){this.y=y;return this}setZ(z){this.z=z;return this}
 copy(v){return this.set(v.x,v.y,v.z)}clone(){return new V(this.x,this.y,this.z)}add(v){this.x+=v.x;this.y+=v.y;this.z+=v.z;return this}sub(v){this.x-=v.x;this.y-=v.y;this.z-=v.z;return this}
 subVectors(a,b){return this.copy(a).sub(b)}addScaledVector(v,n){this.x+=v.x*n;this.y+=v.y*n;this.z+=v.z*n;return this}multiplyScalar(n){this.x*=n;this.y*=n;this.z*=n;return this}
 dot(v){return this.x*v.x+this.y*v.y+this.z*v.z}lengthSq(){return this.dot(this)}length(){return Math.sqrt(this.lengthSq())}normalize(){return this.multiplyScalar(1/(this.length()||1))}
 distanceTo(v){return Math.sqrt(this.distanceToSquared(v))}distanceToSquared(v){return (this.x-v.x)**2+(this.y-v.y)**2+(this.z-v.z)**2}
 crossVectors(a,b){return this.set(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)}lerp(v,n){this.x+=(v.x-this.x)*n;this.y+=(v.y-this.y)*n;this.z+=(v.z-this.z)*n;return this}
 negate(){return this.multiplyScalar(-1)}
}
const f32=Math.fround,native=v=>[v.x,-v.z,v.y],vector=v=>[v.x,v.y,v.z],from=a=>new V(...a),three=a=>new V(a[0],a[2],-a[1]);
const clamp=(v,lo,hi)=>Math.min(hi,Math.max(lo,v));
function hit(origin,direction,max,mode){if(mode===0)return null;if(mode===1)return max>=1.2?1.2:null;const plane=1480.625,d=direction[0]!==0?(plane-origin[0])/direction[0]:-1;return d>=0&&d<=max?d:null}
const context={d:{Pq0:V,cj9:{clamp}},r0:meta.footDistances,r1:Math.PI/4,r5:new Map(meta.footWeaponFov),aa:meta.footSights,ao:h=>180/Math.PI*2*Math.atan(.75*Math.tan(h*Math.PI/360)),tx:{weapon:0},tf:{chuting:false},em:null,W:0,
 eT:0,eP:new V(),eq:new V(),eI:0,tz:0,tR:false,t_:false,tM:0,tj:0,tS:0,tN:70,tA:false,tP:new V(),tT:new V(),tC:2,tE:meta.footDistances[1],tL:null,tD:0,tq:0,tF:{},tI:{},eH:false,eG:0,eD:new V(),eB:new V(),eU:new V(),eW:new V(),eE:false};
context.ai=context.ao(70);for(const [name,sight] of Object.entries(meta.footSights))context.tF[name]=context.tI[name]=sight.first;
vm.createContext(context);let start=source.indexOf('follow(e,t,l){var n,r;let a=arguments.length>3'),stop=source.indexOf('},report(){',start);vm.runInContext('var original=({'+source.slice(start,stop+1)+'})',context);
const camera={position:new V(),fov:45,updateProjectionMatrix(){},getWorldDirection(out){const h=context.input.heading,p=context.input.pitch;return out.set(Math.sin(h)*Math.cos(p),Math.sin(p),-Math.cos(h)*Math.cos(p))}};
context.lT=false;context.lA=true;context.ub={on:false};context.c6={get looks(){return context.tL?[-1.55,1.55]:[context.tR?-1.5533431:-1.4835299,Math.PI/4]}};
const lookStart=source.indexOf('bl=(e,t)=>{if(lT&&'),lookStop=source.indexOf('},bn=60',lookStart);
vm.runInContext('var bl='+source.slice(lookStart+3,lookStop+1),context);
const feet=[];let previousSight=null;
for(let i=0;i<180;i++){
 const input={position:[f32(1480+Math.sin(i*.08)*2),f32(-1738+i*.035),f32(13+Math.max(0,Math.sin(i*.04))*.4)],heading:f32(Math.sin(i*.025)*2),pitch:f32(clamp(-.5+Math.sin(i*.05)*1.1,-1.48,.785)),actorHeading:f32(Math.sin(i*.013)*2),weapon:i<45?22:i<80?30:33,aiming:(i>=20&&i<100)||(i>=140&&i<170),crouching:i>=55&&i<110,holdingLedge:i>=110&&i<120,parachuting:i>=120&&i<135,sight:i>=140&&i<170?'scope':null,zoom:Math.floor(i/30)%3+1,delta:f32(i===0?0:1/60),block:i>=75&&i<105?1:i>=105&&i<140?2:0,scroll:i===145?-1:i===154?-4:0};
 context.input=input;context.tx.weapon=input.weapon;context.tf.chuting=input.parachuting;context.em=input.holdingLedge?{}:null;context.W=-input.actorHeading;context.eE=input.crouching;context.tR=input.aiming&&!input.sight;context.tC=input.zoom;
 if(input.sight!==previousSight){context.tL=input.sight;if(input.sight){context.tF[input.sight]=context.tI[input.sight]=meta.footSights[input.sight].first;context.tq=context.tD=0}previousSight=input.sight}
 if(input.scroll){const s=meta.footSights[input.sight],n=Math.abs(input.scroll)>1?1.084:1.0255**(.07*50);context.tF[input.sight]=clamp(context.tF[input.sight]*(input.scroll<0?1/n:n),s.least,s.most)}
 const collisions=[];context.clear=(o,d,max)=>{collisions.push({origin:native(o),direction:native(d),distance:max});return hit(native(o),native(d),max,input.block)};
 context.camera=camera;context.position=three(input.position);vm.runInContext('original.follow(camera,position,clear,input.delta)',context);
 const expected={source:native(camera.position),fov:camera.fov,aim:context.tA?native(context.tP):null,collisions};
 input.control={type:i%3,x:f32((i%7-3)*(i%3===0?100:i%3===1?3:.25)),y:f32((i%11-5)*(i%3===0?120:i%3===1?2:.18)),sensitivity:f32(1.2),aimSensitivity:f32(.7),inverted:i%2===0};
 const control=input.control;let dx=control.x,dy=control.y;
 // The camera FOV state tN is a number inside follow; use the retained value
 // before replacing the global outer camera object name for pointer handling.
 const fovState=context.tN;context.tN={quaternion:{setFromEuler(){}}};
 const turn=context.tL?context.tI[context.tL]/80:(70+(fovState-70)*context.tj)/70;
 if(control.type===1){const scale=control.sensitivity*2.3*turn*((input.aiming||input.sight)?control.aimSensitivity:1);dx*=scale;dy*=scale*(control.inverted?-1:1)}
 if(control.type===2){const scale=3.2*control.sensitivity*(.3+.7*Math.hypot(control.x,control.y))*turn*((input.aiming||input.sight)?.5:1)*input.delta/.0022;dx*=scale;dy*=scale*.6*(control.inverted?-1:1)}
 context.ch={x:input.pitch,y:-input.heading};context.lookX=dx;context.lookY=dy;vm.runInContext('bl(lookX,lookY)',context);expected.look={heading:-context.ch.y,pitch:context.ch.x};context.tN=fovState;
 feet.push({input,expected});
}
const sandbox={self:{webpackChunk_N_E:[]}};vm.runInNewContext(archive,sandbox);
const modules=Object.assign({},...sandbox.self.webpackChunk_N_E.map(x=>x[1]));function load(id){if(id===85339)return{Pq0:V};if(id===42114)return{S:()=>2,B(){}};const m={exports:{}};modules[id](m,m.exports,load);return m.exports};load.d=(t,o)=>Object.entries(o).forEach(([k,v])=>Object.defineProperty(t,k,{get:v}));
const car=load(98726).Q(),cars=[];let fov=45;
for(let i=0;i<360;i++){
 const kind=['car','bike','heli','plane'][Math.floor(i/90)],view=Math.floor(i/15)%6+1,heading=f32(i*.02),nose=f32(Math.sin(i*.03)*.2),roll=f32(Math.cos(i*.04)*.1),c=Math.cos(heading),s=Math.sin(heading);
 const forward=[s*Math.cos(nose),c*Math.cos(nose),Math.sin(nose)],right=[c*Math.cos(roll),-s*Math.cos(roll),Math.sin(roll)],up=new V().crossVectors(from(right),from(forward)).normalize();
 const input={kind,view,delta:f32(i%90===0?1/30:1/60),position:[f32(1480+i*.06),f32(-1738+i*.11),f32(13+Math.sin(i*.02))],forward:forward.map(f32),right:right.map(f32),up:vector(up).map(f32),moveSpeed:[f32(s*(i%90)/65),f32(c*(i%90)/65),f32(Math.sin(i*.05)*.03)],turnSpeed:[0,0,f32(i%27/100)],wheels:i%18<5?0:4,bounds:{maxX:f32(.9),minY:f32(-2),maxZ:f32(1.6),box:{min:[-.9,-2,-.4].map(f32),max:[.9,2,1.6].map(f32)}},heightAboveRoad:f32(.4),eye:[-.35,.2,.7].map(f32),look:i%50<5?'behind':i%50<10?'left':i%50<15?'right':null,mouse:[f32(i%20<5?2.5:0),f32(i%20<5?-1.7:0)],block:i%40<10?1:0,reset:i%90===0};
 car.setKind(kind);if(input.reset)car.reset();while(car.view!==['near','middle','far','eye','bumper','cinematic'][view-1])car.cycleZoom();
 const n={...input,position:from(input.position),forward:from(input.forward),right:from(input.right),up:from(input.up),moveSpeed:from(input.moveSpeed),turnSpeed:from(input.turnSpeed),heightAboveRoad:input.heightAboveRoad};
 const result=car.process(n,50*input.delta,{x:input.mouse[0],y:input.mouse[1]},input.look),source=vector(result.source),target=vector(result.target),around=vector(result.around),offset=source.map((v,j)=>v-around[j]),distance=Math.hypot(...offset);
 if(distance>1e-4){const direction=offset.map(v=>v/distance),contact=hit(around,direction,distance+.3,input.block);if(contact!==null&&contact<distance+.3)for(let j=0;j<3;j++)source[j]=around[j]+direction[j]*Math.max(0,contact-.3)}
 const desired=context.ao(result.fov);if(Math.abs(desired-fov)>.01)fov=desired;
 cars.push({input,expected:{source,target,fov}});
}
const shaker=load(98726).Q(),shakeContext={eY:0,eG:0,l:{position:new V()},performance:{now:()=>0},Math};
vm.createContext(shakeContext);const shakeStart=archive.indexOf('tl=e=>eY*Math.exp(-2.5*'),shakeStop=archive.indexOf('},tr=',shakeStart);
vm.runInContext('var '+archive.slice(shakeStart,shakeStop+1),shakeContext);
let shakeSeed=177,shakeCalls=0;function shakeRandom(){shakeSeed=(Math.imul(shakeSeed,1664525)+0x3c6ef35f)>>>0;shakeCalls++;return shakeSeed/4294967296}
const shakes=[],shakeInput={position:new V(1480,-1738,13),forward:new V(0,1,0),right:new V(1,0,0),up:new V(0,0,1),moveSpeed:new V(),turnSpeed:new V(),wheels:4,bounds:{maxX:1,minY:-2,maxZ:1.5,box:{min:[-1,-2,-.4],max:[1,2,1.5]}},heightAboveRoad:.4};
for(let i=0;i<360;i++){
 const now=10000+i*20;shakeContext.performance.now=()=>now;
 const event=i===1||i===30||i===50?[1480,-1738,13]:i===10?[2500,-1738,13]:null,strength=i===30?.2:.6;
 if(event)shakeContext.tn(three(event),strength);
 const value=shaker.process(shakeInput,50*Math.fround(.02),{x:0,y:0}),source=vector(value.source),target=vector(value.target);
 shakeContext.l.position=three(source);const amplitude=shakeContext.eY>0?shakeContext.tl(now):0;
 if(amplitude>.002){shakeContext.l.position.add(new V(shakeRandom()-.5,shakeRandom()-.5,shakeRandom()-.5).multiplyScalar(amplitude))}else shakeContext.eY=0;
 shakes.push({now,event,strength,source:native(shakeContext.l.position),target,randomCount:shakeCalls});
}
const projectionStart=source.indexOf('let lx=l_?lA||lT?.15'),projectionStop=source.indexOf(',fy.ue.time.value=',projectionStart);
const projectionContext={l_:true,lA:true,lT:false,a5:0,a9:{farClip:1000},tN:{near:2,far:60000,updateProjectionMatrix(){}},e$:{scale:{setScalar(){}}}};vm.createContext(projectionContext);
const projection=vm.runInContext('(function(){'+source.slice(projectionStart,projectionStop)+';return [tN.near,tN.far]})',projectionContext),planes=[];
for(const [air,farClip] of [[0,1000],[.5,1500],[.999,1500],[1,1500],[1,1500.5],[1,1501],[1,1501.25],[0,300],[1,300],[1,800],[1,800.75],[1,802]]){projectionContext.a5=air;projectionContext.a9.farClip=farClip;planes.push({air,farClip,expected:projection()})}
fs.writeFileSync(process.argv[5],JSON.stringify({feet,cars,shakes,planes}));
'''
SWIFT=r'''
let metadata=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),document=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
func numbers(_ v:Any)->[Float]{(v as! [NSNumber]).map(\.floatValue)}
func v3(_ v:Any)->SIMD3<Float>{let a=numbers(v);return SIMD3(a[0],a[1],a[2])}
var comparisons=0
func close(_ a:Float,_ b:Double,_ label:String){comparisons += 1;assert(abs(Double(a)-b)<0.0005,"\(label): \(a) != \(b)")}
func vec(_ a:SIMD3<Float>,_ b:Any,_ label:String){let values=b as! [Double];for i in 0..<3{close(a[i],values[i],label)}}
func hit(_ origin:SIMD3<Float>,_ direction:SIMD3<Float>,_ max:Float,_ mode:Int)->Float?{if mode==0{return nil};if mode==1{return max>=1.2 ? 1.2:nil};let distance=direction.x != 0 ? (1480.625-origin.x)/direction.x : -1;return distance>=0&&distance<=max ? distance:nil}
let foot=try NativeGameCamera(data:metadata)
for (index,item) in (document["feet"] as! [[String:Any]]).enumerated(){
 let input=item["input"] as! [String:Any],expected=item["expected"] as! [String:Any]
 let sight=input["sight"] as? String
 let state=NativeGameCamera.Foot(position:v3(input["position"]!),actorHeading:(input["actorHeading"] as! NSNumber).floatValue,weapon:input["weapon"] as! Int,aiming:input["aiming"] as! Bool,crouching:input["crouching"] as! Bool,holdingLedge:input["holdingLedge"] as! Bool,parachuting:input["parachuting"] as! Bool,sight:sight)
 foot.setDirection(heading:(input["heading"] as! NSNumber).floatValue,pitch:(input["pitch"] as! NSNumber).floatValue);foot.setFootZoom(input["zoom"] as! Int)
 var calls:[(SIMD3<Float>,SIMD3<Float>,Float)]=[]
 foot.trace={o,d,m in calls.append((o,d,m));return hit(o,d,m,input["block"] as! Int)}
 if let scroll=input["scroll"] as? Int,scroll != 0{foot.zoomSight(Float(scroll))}
 let frame=foot.followFoot(state,delta:(input["delta"] as! NSNumber).floatValue)!
 vec(frame.source,expected["source"]!,"foot source frame \(index)");close(frame.verticalFov,expected["fov"] as! Double,"foot fov frame \(index)")
 if let aim=expected["aim"] as? [Double]{vec(frame.aimSource!,aim,"aim source")}else{assert(frame.aimSource==nil)}
 let original=expected["collisions"] as! [[String:Any]];assert(calls.count==original.count,"trace count")
 for (call,test) in zip(calls,original){vec(call.0,test["origin"]!,"trace origin");vec(call.1,test["direction"]!,"trace direction");close(call.2,test["distance"] as! Double,"trace distance")}
 let control=input["control"] as! [String:Any],dx=(control["x"] as! NSNumber).floatValue,dy=(control["y"] as! NSNumber).floatValue
 switch control["type"] as! Int {
 case 1:foot.lookTouch(x:dx,y:dy,sensitivity:(control["sensitivity"] as! NSNumber).floatValue,aimSensitivity:(control["aimSensitivity"] as! NSNumber).floatValue,inverted:control["inverted"] as! Bool)
 case 2:foot.lookAnalog(x:dx,y:dy,delta:(input["delta"] as! NSNumber).floatValue,sensitivity:(control["sensitivity"] as! NSNumber).floatValue,inverted:control["inverted"] as! Bool)
 default:foot.lookPixels(x:dx,y:dy)
 }
 let orientation=expected["look"] as! [String:Double];close(foot.heading,orientation["heading"]!,"look heading");close(foot.pitch,orientation["pitch"]!,"look pitch")

}
let car=try NativeGameCamera(data:metadata)
for (index,item) in (document["cars"] as! [[String:Any]]).enumerated(){
 let input=item["input"] as! [String:Any],expected=item["expected"] as! [String:Any],b=input["bounds"] as! [String:Any],box=b["box"] as! [String:Any]
 let bounds=NativeGameCamera.Bounds(maxX:(b["maxX"] as! NSNumber).floatValue,minY:(b["minY"] as! NSNumber).floatValue,maxZ:(b["maxZ"] as! NSNumber).floatValue,min:v3(box["min"]!),max:v3(box["max"]!))
 let state=NativeGameCamera.Vehicle(kind:input["kind"] as! String,position:v3(input["position"]!),forward:v3(input["forward"]!),right:v3(input["right"]!),up:v3(input["up"]!),moveSpeed:v3(input["moveSpeed"]!),turnSpeed:v3(input["turnSpeed"]!),wheels:input["wheels"] as! Int,bounds:bounds,heightAboveRoad:(input["heightAboveRoad"] as! NSNumber).floatValue,eye:v3(input["eye"]!))
 car.setVehicleKind(input["kind"] as! String);if input["reset"] as! Bool{car.resetVehicle()};car.setVehicleView(input["view"] as! Int)
 let mouse=numbers(input["mouse"]!);car.lookPixels(x:mouse[0],y:mouse[1],driving:true);car.trace={o,d,m in hit(o,d,m,input["block"] as! Int)}
 let frame=car.followVehicle(state,delta:(input["delta"] as! NSNumber).floatValue,look:input["look"] as? String)!
 vec(frame.source,expected["source"]!,"car source frame \(index)");vec(frame.target,expected["target"]!,"car target frame \(index)");close(frame.verticalFov,expected["fov"] as! Double,"car fov frame \(index)")
}
let shaker=try NativeGameCamera(data:metadata)
var shakeSeed:UInt32=177,shakeCount=0
let shakeInput=NativeGameCamera.Vehicle(position:SIMD3(1480,-1738,13),forward:SIMD3(0,1,0),right:SIMD3(1,0,0),up:SIMD3(0,0,1),bounds:.init(maxX:1,minY:-2,maxZ:1.5,min:SIMD3(-1,-2,-0.4),max:SIMD3(1,2,1.5)),heightAboveRoad:0.4)
for item in document["shakes"] as! [[String:Any]] {
 let now=item["now"] as! Double
 if let event=item["event"] as? [Double]{shaker.shake(at:SIMD3(Float(event[0]),Float(event[1]),Float(event[2])),strength:(item["strength"] as! NSNumber).floatValue,nowMilliseconds:now)}
 let value=shaker.followVehicle(shakeInput,delta:0.02,nowMilliseconds:now,random:{shakeSeed=shakeSeed &* 1664525 &+ 0x3c6ef35f;shakeCount += 1;return Double(shakeSeed)/4294967296})!
 vec(value.source,item["source"]!,"shake source");vec(value.target,item["target"]!,"shake target");assert(shakeCount==item["randomCount"] as! Int)
}
let projection=try NativeGameCamera(data:metadata)
for item in document["planes"] as! [[String:Any]]{let value=projection.projection(air:(item["air"] as! NSNumber).floatValue,farClip:(item["farClip"] as! NSNumber).floatValue),expected=item["expected"] as! [Double];close(value.near,expected[0],"near plane");close(value.far,expected[1],"far plane")}
print("PASS: 180 original on-foot and 360 original vehicle camera frames, all six views, aim/scope/crouch/ledge/parachute transitions, FOV and collision margins, plus 360 original shake frames and projection deadband; \(comparisons) comparisons")
'''

def main():
 chunks=ROOT/'local-only/site/_next/static/chunks'
 main=next(p for p in chunks.glob('*.js') if 'yM=[...wD.c$,24]' in p.read_text())
 vehicle=next(p for p in chunks.glob('*.js') if '98726:(e,t,l)' in p.read_text())
 data=ROOT/'local-only/site/game/native/camera.json'
 with tempfile.TemporaryDirectory(prefix='zgta-camera-') as tmp:
  work=Path(tmp);js=work/'reference.js';js.write_text(JS);reference=work/'reference.json'
  subprocess.run(['node',str(js),str(main),str(vehicle),str(data),str(reference)],check=True)
  swift=work/'verify.swift';swift.write_text(''.join((ROOT/f'ios/App/{n}.swift').read_text() for n in ['ServerAddress','NativeGameCamera'])+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(swift),str(data),str(reference)],check=True)
if __name__=='__main__':main()
