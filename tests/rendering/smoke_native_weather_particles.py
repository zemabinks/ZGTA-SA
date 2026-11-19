#!/usr/bin/env python3
"""Exercise the archived weather manager and compare native visual simulation.

Voice is disabled in both runs. The original JS's buffers drive the independent
particle-vertex reference; flat ground z=13 isolates timing and spawn behavior.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),source=fs.readFileSync(process.argv[2],'utf8'),meta=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
class V{
 constructor(x=0,y=0,z=0){this.set(x,y,z)}set(x,y,z){Object.assign(this,{x,y,z});return this}copy(v){return this.set(v.x,v.y,v.z)}
 setScalar(n){return this.set(n,n,n)}toArray(){return [this.x,this.y,this.z]}
 setRGB(x,y,z,space){const linear=v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4;return space==='srgb'?this.set(linear(x),linear(y),linear(z)):this.set(x,y,z)}
}
class Geometry{constructor(){this.attributes={}}setAttribute(k,v){this.attributes[k]=v;return this}setIndex(v){this.index=v;return this}dispose(){}}
class Attribute{constructor(array,size){this.array=array;this.itemSize=size;this.updateRanges=[]}setUsage(){return this}clearUpdateRanges(){this.updateRanges=[]}addUpdateRange(start,count){this.updateRanges.push({start,count})}}
class Material{constructor(v){Object.assign(this,v)}dispose(){}}
class Mesh{constructor(geometry,material){Object.assign(this,{geometry,material,visible:false})}}
const objects=[],scene={add(...m){objects.push(...m)},remove(){}},d={Pq0:V,Q1f:V,I9Y:V,LoY:Geometry,CmU:Geometry,THS:Attribute,LuO:Attribute,eHs:Attribute,BKk:Material,eaF:Mesh,DXC:Mesh,er$:'srgb',cj9:{degToRad:x=>x*Math.PI/180}};
let seed=44157,randomCount=0;const math=Object.create(Math);math.random=()=>{seed=(Math.imul(seed,1664525)+0x3c6ef35f)>>>0;randomCount++;return seed/4294967296};
const context={d,Math:math,mx:{LO:meta.wind,ZL:meta.gusts,Li:meta.directions},fq:()=>({then:fn=>fn({textures:new Map(['splash_up1','splash_up2','bullethitsmoke','cloudmasked'].map(name=>[name,{name}]))})})};
context.input={scene,below:(p,drop)=>p.y-13,voice:()=>null};
vm.createContext(context);const begin=source.indexOf('w4=[8,16]'),end=source.indexOf('let yM=',begin);vm.runInContext('let '+source.slice(begin,end),context);
const start=source.indexOf('function(e){let{scene:t,below:l,voice:n}=e'),stop=source.indexOf('}({scene:eV,below:',start);vm.runInContext('var weather=('+source.slice(start,stop+1)+')(input)',context);
const camera={position:new V(1480,13,1738),getWorldDirection(out){return out.set(0,-.2,-Math.sqrt(.96))}};
context.camera=camera;const frames=[];
function run(count,from,to,blend,outdoors,delta=1/30){for(let frame=0;frame<count;frame++)frames.push({from,to,blend:Math.fround(blend),outdoors,delta:Math.fround(delta),capture:frame===0||frame===1||frame===10||frame===30||frame===60||frame===count-1})}
run(1,10,10,1,true);run(80,8,8,1,true);run(15,8,10,.3,true);run(120,9,9,1,true);run(45,19,19,1,true);run(20,8,8,1,false);run(180,10,10,1,true);run(500,8,8,1,true);run(2,16,16,1,true,.5);
const native=v=>[v[0],-v[2],v[1]],capture=[];
function sprite(mesh,kind,clock){
 const uniform=mesh.material.uniforms,a=mesh.geometry.attributes.place.array.array,now=clock,result=[];
 // Interleaved attributes all point to one Float32Array in the actual helper.
 for(let offset=0;offset<a.length;offset+=16){
  const age=now-a[offset+3],share=age/Math.max(a[offset+7],.0001);
  if(age<0||share>=1)continue;
  const center=[a[offset]+a[offset+4]*age,a[offset+1]+a[offset+5]*age,a[offset+2]+a[offset+6]*age];
  const distance=Math.hypot(center[0]-1480,center[1]-13,center[2]-1738),near=kind===2?42:30,far=kind===2?60:50;
  const fade=kind===0?1-share:kind===1?Math.min(share/.1,(1-share)/.9):Math.min(age/.3,1);
  const alpha=a[offset+15]*fade*Math.min(1,Math.max(0,(far-distance)/(far-near)))*(kind===2?uniform.strength.value:1);
  if(alpha<=0)continue;
  const size=a[offset+8]*(1-share)+a[offset+9]*share,angle=a[offset+10]+a[offset+11]*age,c=Math.cos(angle),s=Math.sin(angle),shade=uniform.shade.value;
  result.push({texture:kind===0?(share<.25?'splash_up1':'splash_up2'):kind===1?'bullethitsmoke':'cloudmasked',center:native(center),right:[c*size*.5,0,s*size*.5],up:[-s*size*.5,0,c*size*.5],tint:[a[offset+12]*shade.x,a[offset+13]*shade.y,a[offset+14]*shade.z,alpha]});
 }
 return result;
}
for(const frame of frames){
 context.frame=frame;vm.runInContext('weather.update(frame.delta,camera,frame.from,frame.to,frame.blend,frame.outdoors,[.4,.5,.6])',context);
 const state=vm.runInContext('weather.state()',context);frame.randomCount=randomCount;
 if(frame.capture){
  const line=objects[0],positions=line.geometry.attributes.position.array,alpha=line.geometry.attributes.solid.array;
  const lines=[];if(line.visible)for(let i=0;i<32;i++)lines.push({from:native(Array.from(positions.slice(i*6,i*6+3))),to:native(Array.from(positions.slice(i*6+3,i*6+6))),alpha:Array.from(alpha.slice(i*2,i*2+2))});
  frame.expected={state,lines,quads:[...sprite(objects[1],0,state.clock),...sprite(objects[2],1,state.clock),...(objects[3].visible?sprite(objects[3],2,state.clock):[])]};capture.push(frame);
 }
}
fs.writeFileSync(process.argv[4],JSON.stringify(frames));console.log(`Reference: ${frames.length} weather frames, ${capture.length} captured frames, ${randomCount} random calls`);
'''
SWIFT=r'''
let weather=try NativeWeatherParticles(data:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]]
var seed:UInt32=44157,randomCount=0,comparisons=0,captures=0
func close(_ actual:Float,_ expected:Double,_ label:String){comparisons += 1;assert(abs(Double(actual)-expected)<0.002,"\(label): \(actual) != \(expected)")}
func vector(_ actual:SIMD3<Float>,_ expected:[Double],_ label:String){for i in 0..<3{close(actual[i],expected[i],label)}}
let aim=SIMD3<Float>(0,Float(sqrt(0.96)),-0.2)
for (index,item) in cases.enumerated(){
 let value=weather.update(delta:(item["delta"] as! NSNumber).floatValue,camera:SIMD3(1480,-1738,13),forward:aim,cameraRight:SIMD3(1,0,0),cameraUp:SIMD3(0,0,1),weatherFrom:item["from"] as! Int,weatherTo:item["to"] as! Int,blend:(item["blend"] as! NSNumber).floatValue,skyTop:SIMD3(0.4,0.5,0.6),outdoors:item["outdoors"] as! Bool,ground:{_,_,_,_ in 13},random:{seed=seed &* 1664525 &+ 0x3c6ef35f;randomCount += 1;return Double(seed)/4294967296})!
 assert(randomCount==item["randomCount"] as! Int,"random sequence differs at frame \(index): \(randomCount) != \(item["randomCount"]!)")
 guard let expected=item["expected"] as? [String:Any] else{continue};captures += 1
 let state=expected["state"] as! [String:Any]
 for (key,actual) in [("clock",value.clock),("rain",value.rain),("sand",value.sand),("wind",value.wind),("foggy",value.fog),("fogIn",value.fogIn),("hazeAlpha",value.hazeAlpha)]{close(actual,state[key] as! Double,key)}
 let way=state["way"] as! [Double];vector(value.windVector,[way[0],-way[2],way[1]],"wind")
 assert(value.flash==state["flash"] as! Bool && value.bursting==state["bursting"] as! Bool)
 assert(value.bursts==state["bursts"] as! Int && value.claps==state["claps"] as! Int && value.streaks==state["streaks"] as! Int)
 let lines=expected["lines"] as! [[String:Any]];assert(value.lines.count==lines.count)
 for (actual,line) in zip(value.lines,lines){vector(actual.from,line["from"] as! [Double],"rain line");vector(actual.to,line["to"] as! [Double],"rain tip");let a=line["alpha"] as! [Double];close(actual.fromAlpha,a[0],"line alpha");close(actual.toAlpha,a[1],"tip alpha")}
 let quads=expected["quads"] as! [[String:Any]];assert(value.quads.count==quads.count,"quad count at \(index): \(value.quads.count) != \(quads.count)")
 for (actual,quad) in zip(value.quads,quads){assert(actual.texture==quad["texture"] as! String);vector(actual.center,quad["center"] as! [Double],"particle center");vector(actual.right,quad["right"] as! [Double],"particle right");vector(actual.up,quad["up"] as! [Double],"particle up");let tint=quad["tint"] as! [Double];for i in 0..<4{close(actual.tint[i],tint[i],"particle tint")}}
}
print("PASS: \(cases.count) archived JS weather frames / \(captures) visual captures; \(comparisons) comparisons, rain/splashes/haze/fog/gusts/lightning; \(randomCount) matching random calls")
'''


def main():
    chunks=ROOT/'local-only/site/_next/static/chunks'
    source=next(p for p in chunks.glob('*.js') if 'function(e){let{scene:t,below:l,voice:n}=e' in p.read_text())
    data=ROOT/'local-only/site/game/native/atmosphere.json'
    with tempfile.TemporaryDirectory(prefix='zgta-weather-particles-') as tmp:
        work=Path(tmp);js=work/'reference.js';js.write_text(JS);reference=work/'reference.json'
        subprocess.run(['node',str(js),str(source),str(data),str(reference)],check=True)
        swift=work/'verify.swift';swift.write_text(''.join((ROOT/f'ios/App/{n}.swift').read_text() for n in ['ServerAddress','NativeWorldEnvironment','NativeAtmosphere','NativeWeatherAudio','NativeWeatherParticles'])+SWIFT)
        subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(swift),str(data),str(reference)],check=True)


if __name__=='__main__':main()
