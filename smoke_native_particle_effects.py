#!/usr/bin/env python3
"""Compare original generic FX core using archived 48-system definitions."""
from pathlib import Path
import subprocess
from smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),T=load(85339),source=fs.readFileSync('local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js','utf8'),data=JSON.parse(fs.readFileSync('local-only/site/game/world/fx.json'));
const textures=load(88711).XC([load(52528).nk(fs.readFileSync('local-only/site/game/effectspc.txd'))]),pictures=new Map([...textures.keys()].map((name,index)=>[name,[0,index]]));
const fD=source.slice(source.indexOf('function fD('),source.indexOf('let fB=',source.indexOf('function fD('))),fU=source.slice(source.indexOf('let fB='),source.indexOf(';var fW=',source.indexOf('let fB=')))+';',start=source.indexOf('for(let e of Object.values(l))e.emitters'),end=source.indexOf('}(t,e,{water:',start),core=source.slice(start,end),prefix='let a=Array.from({length:1024},()=>fU(false)),o=Array.from({length:96},()=>fU(true)),i=a.concat(o),s=0,c=new Uint8Array(i.length);';
const original=factory.constructor('d','l','n','r','hg','m',fD+fU+prefix+core)(T,data.systems,textures,{water:()=>0},{r3:()=>1},{where:name=>pictures.get(name)??null,dispose(){}});
let seed=987654321,calls=0;g.Math.random=()=>{calls++;return((seed=(Math.imul(seed,1664525)+1013904223)>>>0)/4294967296)};
const names=Object.keys(data.systems),anchor=new T.Pq0,rows=[],seeds=[],quat=new T.PTz().setFromAxisAngle(new T.Pq0(0,1,0),.3),tint=new T.Q1f(.8,.7,.6),vec=v=>[v.x,-v.z,v.y];
for(let frame=0;frame<2400;frame++){
 const name=names[Math.floor(frame/40)%names.length],delta=[1/60,1/50,1/75][frame%3],position=new T.Pq0(Math.sin(frame*.013)*2,Math.sin(frame*.007)*2,Math.cos(frame*.011)*2),velocity=new T.Pq0(.3,-.2,.4),clock=(frame%120)/120,mult={size:.4,life:.8,alpha:.6},useAnchor=frame%80<30,water=frame%90<45?null:1;
 anchor.set(Math.sin(frame*.023)*.2,Math.cos(frame*.029)*.2,Math.sin(frame*.017)*.2);
 original.burst(name,position,delta,{time:clock,velocity,scale:.6,tint,turn:quat,anchor:useAnchor?anchor:null,water,mult});
 if(frame%80===0)original.play(name,position,{water});
 if(frame%7===0)original.particles(name,position,velocity,3,{jitter:.2,tint,mult,floor:0,angle:.1,anchor:useAnchor?anchor:null,water});
 const brightness=.6+Math.sin(frame*.019)*.4;original.update(delta,brightness);
 seeds.push([seed,calls]);if(frame%10===0){const particles=original.shown().particles.map((p,index)=>({index,flat:!!p.flat,texture:p.emitter.texture,position:vec(p.position),velocity:vec(p.velocity),age:p.age,life:p.life,born:p.born,wide:p.wide,tall:p.tall,turned:p.turned,across:p.across,up:p.up,color:[p.red,p.green,p.blue],shows:p.shows,adds:!!p.adds,trail:p.trail}));rows.push({frame,particles})}
}
fs.writeFileSync(process.argv[2],JSON.stringify({textures:[...textures.keys()],names,rows,seeds}));
'''
SWIFT=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1]),doc=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))).any as! [String:Any],textures=Set(doc["textures"] as! [String]),names=doc["names"] as! [String],rows=doc["rows"] as! [[String:Any]]
var seed:UInt32=987654321,calls=0
let engine=try NativeParticleEffects(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/world/fx.json")),textures:textures,random:{calls+=1;seed=seed&*1664525&+1013904223;return Double(seed)/4294967296}),anchor=NativeParticleEffects.Anchor(.zero)
engine.water={_ in 0}
var maximum:Double=0,checks=0,states=0
func compare(_ a:Double,_ b:Double,_ label:String){let error=abs(a-b);maximum=max(maximum,error);assert(error<0.00000001,"\(label): \(a) vs \(b), error\(error)");checks+=1}
func vector(_ a:[NSNumber])->SIMD3<Double>{SIMD3(a[0].doubleValue,a[1].doubleValue,a[2].doubleValue)}
for frame in 0..<2400 {
 let name=names[(frame/40)%names.count],delta=[1.0/60,1.0/50,1.0/75][frame%3],f=Double(frame),position=SIMD3(sin(f*0.013)*2,-cos(f*0.011)*2,sin(f*0.007)*2),velocity=SIMD3(0.3,-0.4,-0.2),clock=Double(frame%120)/120,mult=NativeParticleEffects.Multiplier(size:0.4,life:0.8,alpha:0.6),useAnchor=frame%80<30,water:Double?=frame%90<45 ? nil:1
 anchor.position=SIMD3(sin(f*0.023)*0.2,-sin(f*0.017)*0.2,cos(f*0.029)*0.2)
 engine.burst(name,at:position,delta:delta,options:.init(time:clock,velocity:velocity,scale:0.6,tint:SIMD3(0.8,0.7,0.6),turn:simd_quatd(angle:0.3,axis:SIMD3(0,0,1)),anchor:useAnchor ? anchor:nil,water:water,mult:mult))
 if frame%80==0{engine.play(name,at:position,water:water)}
 if frame%7==0{engine.spawn(name,at:position,velocity:velocity,count:3,options:.init(jitter:0.2,tint:SIMD3(0.8,0.7,0.6),mult:mult,floor:0,angle:0.1,anchor:useAnchor ? anchor:nil,water:water))}
 engine.update(delta:delta,brightness:0.6+sin(f*0.019)*0.4)
 let rng=(doc["seeds"] as! [[NSNumber]])[frame];assert(UInt32(rng[0].uint32Value)==seed,"frame\(frame) RNG seed native\(seed) / source\(rng[0]), calls\(calls) / source\(rng[1])")
 if frame%10==0 {
  let expected=rows[frame/10]["particles"] as! [[String:Any]],actual=engine.shown
  assert(expected.count==actual.count,"frame\(frame) count \(actual.count) vs \(expected.count)")
  for(index,p)in actual.enumerated(){let other=expected[index];assert(p.flat==other["flat"] as! Bool && p.adds==other["adds"] as! Bool && p.emitter!.texture==other["texture"] as! String,"frame\(frame) identity\(index)")
   for(key,value)in[("position",p.position),("velocity",p.velocity),("color",p.color)]{let expected=vector(other[key] as! [NSNumber]);for axis in 0..<3{compare(value[axis],expected[axis],"frame\(frame) particle\(index) \(key).\(axis)")}}
   for(key,value)in[("age",p.age),("life",p.life),("born",p.born),("wide",p.wide),("tall",p.tall),("turned",p.turned),("across",p.across),("up",p.up),("shows",p.shows),("trail",p.trail)]{compare(value,(other[key] as! NSNumber).doubleValue,"frame\(frame) particle\(index) \(key)")};states+=1
  }
 }
}
print("PASS: 2400 original particle core frames, \(states) live particle snapshots, \(checks) emission/lifetime/motion/size/color/rotation checks; maxerror \(maximum)")
'''
def main():
 work=Path('/private/tmp/zgta-particle-effects-debug');work.mkdir(exist_ok=True);(work/'reference.js').write_text(JS)
 subprocess.run(['node',str(work/'reference.js'),str(work/'reference.json')],cwd=ROOT,check=True)
 (work/'verify.swift').write_text((ROOT/'ios/App/NativeParticleEffects.swift').read_text()+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
 subprocess.run(['swiftc','-Onone','-whole-module-optimization','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),'-o',str(work/'verify')],check=True)
 subprocess.run([str(work/'verify'),str(ROOT),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
