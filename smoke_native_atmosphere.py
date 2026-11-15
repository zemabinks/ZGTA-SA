#!/usr/bin/env python3
"""Compare native sky/cloud state to the actual archived JavaScript factory.

The JS runs offline with minimal Three data containers: it is the original
factory/update code, not a duplicate implementation of the sky calculations.
Cloud vertex positions are checked separately against their shader equations.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
JAVASCRIPT = r'''
const fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(process.argv[2],'utf8'),meta=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
const archive=process.argv[4],sandbox={self:{webpackChunk_N_E:[]}};
vm.runInNewContext(fs.readFileSync(archive,'utf8'),sandbox);
const modules=Object.assign({},...sandbox.self.webpackChunk_N_E.map(x=>x[1])),cache={};
function load(id){if(cache[id])return cache[id].exports;const m={exports:{}};cache[id]=m;modules[id](m,m.exports,load);return m.exports}
load.d=(t,o)=>Object.entries(o).forEach(([k,v])=>Object.defineProperty(t,k,{get:v}));
class Vector{
 constructor(x=0,y=0,z=0){this.set(x,y,z)}set(x,y,z){Object.assign(this,{x,y,z});return this}
 setRGB(x,y,z){return this.set(x,y,z)}setY(y){this.y=y;return this}clone(){return new Vector(this.x,this.y,this.z)}
 copy(v){return this.set(v.x,v.y,v.z)}normalize(){return this.multiplyScalar(1/(Math.hypot(this.x,this.y,this.z)||1))}
 multiplyScalar(n){this.x*=n;this.y*=n;this.z*=n;return this}negate(){return this.multiplyScalar(-1)}
 crossVectors(a,b){return this.set(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)}
}
class Geometry{constructor(){this.attributes={}}setAttribute(k,v){this.attributes[k]=v;return this}setIndex(v){this.index=v;return this}translate(){return this}dispose(){}}
class Attribute{constructor(array,size){this.array=array;this.itemSize=size}}
class Material{constructor(v){Object.assign(this,v)}dispose(){}}
class Mesh{constructor(geometry,material){Object.assign(this,{geometry,material,visible:false})}}
const objects=[],scene={add(...o){objects.push(...o)},remove(){}},dome={material:{uniforms:{below:{value:new Vector()},indoors:{value:0},high:{value:new Vector()},low:{value:new Vector()}}}};
const d={Pq0:Vector,Q1f:Vector,CmU:Geometry,LoY:Geometry,bdM:Geometry,THS:Attribute,uWO:Attribute,BKk:Material,eaF:Mesh,N1A:Mesh,cj9:{degToRad:x=>x*Math.PI/180}};
const context={d,wD:{c$:meta.hours,Ge:meta.colors},wB:load(98459),w3:load(7508),fH:{z:()=>({then:fn=>fn(name=>({name}))})},hg:{r3:()=>1},fy:{ue:{gameFog:{value:1},flash:{value:0},hazeColor:{value:new Vector()}},Nw(){}},Math:Object.create(Math)};
Object.assign(context,meta.constants);
context.w5=(list,value)=>+list.includes(value);context.wU=2*Math.tan(35*Math.PI/180);context.wK=2.1;
context.wX='sheets';context.wZ='high';context.w0='rainbow';context.w1='meteor';
context.w2=(shader,uniforms)=>new Material({shader,uniforms});
context.yk=(from,to,blend)=>(meta.wind[from]||0)*(1-blend)+(meta.wind[to]||0)*blend;
const begin=source.indexOf('let yM=[...wD.c$,24]'),end=source.indexOf('let yK=',begin);
vm.createContext(context);vm.runInContext(source.slice(begin,end),context);
const start=source.indexOf('function(e){let{scene:t,dome:l,ambient:n,sun:r}=e'),stop=source.indexOf('}({scene:eV,dome:e$,ambient:eX,sun:eZ});',start);
context.input={scene,dome,ambient:{intensity:1,color:new Vector()},sun:{intensity:1,color:new Vector(),position:new Vector(-.5,Math.SQRT1_2,.5)}};
vm.runInContext('var sky=('+source.slice(start,stop+1)+')(input)',context);
const native=v=>[v[0],-v[2],v[1]],color=v=>[v.x,v.y,v.z];
const result=[];
function capture(mesh){const a=mesh.geometry.attributes;return {visible:mesh.visible,centers:a.centre?Array.from(a.centre.array):null,sizes:a.reach?Array.from(a.reach.array):null,tints:a.tint?Array.from(a.tint.array):null}}
const points=[
 {hour:3.5,from:0,to:0,blend:1,z:13,delta:.016},
 {hour:3.5,from:0,to:0,blend:1,z:13,delta:.006},
 {hour:5.5,from:3,to:1,blend:.4,z:120,delta:.04},
 {hour:6.5,from:1,to:10,blend:.2,z:13,delta:.05},
 {hour:12,from:10,to:10,blend:1,z:13,delta:.1},
 {hour:12,from:7,to:10,blend:.25,z:13,delta:.1},
 {hour:12,from:7,to:7,blend:1,z:240,delta:.7},
 {hour:19.5,from:19,to:9,blend:.4,z:240,delta:.6},
 {hour:22.5,from:4,to:4,blend:1,z:400,delta:.3},
 {hour:23.999,from:0,to:0,blend:1,z:13,delta:.5},
 {hour:3.5,from:0,to:0,blend:1,z:13,delta:6},
 {hour:12,from:7,to:7,blend:1,z:240,delta:1,interior:0}
];
let randomCounter=0;context.Math.random=()=>((randomCounter++*17+11)%97)/97;
for(const input of points){
 for(const key of ['hour','blend','z','delta'])input[key]=Math.fround(input[key]);
 const camera={position:new Vector(1480,input.z,1738),far:1000};context.camera=camera;context.sample=input;
 vm.runInContext('sky.update(camera,sample.hour,sample.from,sample.to,sample.blend,sample.delta,sample.interior??null)',context);
 const environment=load(7508)._$ (input.hour,input.from,input.to,input.blend,input.z);
 const sheet=objects[4],high=objects[5],rainbow=objects[6],meteor=objects[7];
 result.push({input,environment,sprites:objects.slice(0,4).map(capture),below:color(dome.material.uniforms.below.value),
  sheet:{visible:sheet.visible,drift:sheet.material.uniforms.drifted.value,solid:sheet.material.uniforms.solid.value,tint:color(sheet.material.uniforms.tint.value),bright:color(sheet.material.uniforms.bright.value)},
  high:{visible:high.visible,drift:color(high.material.uniforms.drift.value),grey:color(high.material.uniforms.grey.value),reach:high.material.uniforms.reach.value,faded:high.material.uniforms.faded.value},
  rainbow:rainbow.visible?{middle:color(rainbow.material.uniforms.middle.value),across:color(rainbow.material.uniforms.across.value),over:color(rainbow.material.uniforms.over.value),strength:rainbow.material.uniforms.strength.value}:null,
  meteor:meteor.visible?{from:color(meteor.material.uniforms.from.value),along:color(meteor.material.uniforms.along.value),gone:meteor.material.uniforms.gone.value}:null});
}
const sheetGeometry=objects[4].geometry.attributes,highGeometry=objects[5].geometry.attributes;
for(let i=0;i<58;i++)for(let axis=0;axis<4;axis++)if(meta.sheets[i].spot[axis]!==sheetGeometry.spot.array[i*4+axis])throw Error('sheet extraction mismatch');
for(let i=0;i<58;i++)for(let axis=0;axis<3;axis++)if(meta.sheets[i].span[axis]!==sheetGeometry.span.array[i*3+axis])throw Error('sheet extraction mismatch');
for(let i=0;i<180;i++){
 for(let axis=0;axis<3;axis++)if(meta.highClouds[i].home[axis]!==highGeometry.home.array[i*3+axis]||meta.highClouds[i].girth[axis]!==highGeometry.girth.array[i*3+axis])throw Error('volume extraction mismatch');
 if(meta.highClouds[i].density!==highGeometry.dense.array[i])throw Error('volume density mismatch');
}
fs.writeFileSync(process.argv[5],JSON.stringify(result));
'''

SWIFT = r'''
let atmosphere = try NativeAtmosphere(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String:Any]]
let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String:Any]
var randomCounter=0, comparisons=0
func close(_ actual: Float,_ expected: Double,_ name: String) { comparisons += 1; assert(abs(Double(actual)-expected)<0.002,"\(name): \(actual) != \(expected)") }
func vector(_ actual: SIMD3<Float>,_ expected: [Double],_ name: String) {for i in 0..<3 {close(actual[i],expected[i],name)}}
func native(_ x: [Double])->[Double] { [x[0],-x[2],x[1]] }
func mod(_ x:Double,_ y:Double)->Double {x-floor(x/y)*y}
var elapsed: Float = 0
for test in cases {
 let input=test["input"] as! [String:Any], environment=test["environment"] as! [String:Any]
 func f(_ key:String)->Float {(input[key] as! NSNumber).floatValue}
 func e(_ key:String)->[Double] {(environment[key] as! [NSNumber]).map(\.doubleValue)}
 let sky=e("skyTop"),bottom=e("skyBottom"),water=e("water")
 let conditions=NativeWorldEnvironment.Conditions(skyTop:SIMD4(Float(sky[0]),Float(sky[1]),Float(sky[2]),1),skyBottom:SIMD4(Float(bottom[0]),Float(bottom[1]),Float(bottom[2]),1),waterColor:SIMD4(Float(water[0]),Float(water[1]),Float(water[2]),Float(water[3])),farClip:(environment["farClip"] as! NSNumber).floatValue,fogStart:(environment["fogStart"] as! NSNumber).floatValue)
 let camera=SIMD3<Float>(1480,-1738,f("z"))
 let actual=atmosphere.update(delta:f("delta"),hour:f("hour"),weatherFrom:input["from"] as! Int,weatherTo:input["to"] as! Int,blend:f("blend"),camera:camera,cameraFar:1000,cameraRight:SIMD3(1,0,0),cameraUp:SIMD3(0,0,1),conditions:conditions,interiorColor:input["interior"] as? Int,random:{ defer {randomCounter += 1}; return Double((randomCounter*17+11)%97)/97 })!
 vector(actual.belowColor,(test["below"] as! [NSNumber]).map(\.doubleValue),"below")
 let sprites=test["sprites"] as! [[String:Any]]
 // The factory adds moon, stars, horizon, sun; native emits sun first.
 var nativeSprites=Array(actual.quads.filter {$0.blend == .additive})
 let order=[3,0,1,2]
 for index in order {
  let expected=sprites[index]
  guard expected["visible"] as! Bool else {continue}
  let centers=(expected["centers"] as! [NSNumber]).map(\.doubleValue),sizes=(expected["sizes"] as! [NSNumber]).map(\.doubleValue),tints=(expected["tints"] as! [NSNumber]).map(\.doubleValue)
  for i in 0..<centers.count/3 {
   let quad=nativeSprites.removeFirst();var center=native(Array(centers[i*3..<i*3+3]))
   center[0]+=1480;center[1] += -1738;if index != 2 {center[2]+=Double(f("z"))}
   vector(quad.center,center,"sprite center")
   close(simd_length(quad.right),sizes[i*2],"sprite width");close(simd_length(quad.up),sizes[i*2+1],"sprite height")
   for j in 0..<3 {close(quad.tint[j],tints[i*3+j],"sprite tint")}
  }
 }
 assert(nativeSprites.isEmpty)
 let sheet=test["sheet"] as! [String:Any],vol=test["high"] as! [String:Any]
 // Reference evaluation of the archived cloud vertex shader equations.
 var sheets:[([Double],Double,[Double],[Double]?)]=[]
 if sheet["visible"] as! Bool {
  let drift=sheet["drift"] as! Double,solid=sheet["solid"] as! Double,tint=sheet["tint"] as! [Double],bright=sheet["bright"] as! [Double]
  for item in metadata["sheets"] as! [[String:Any]] {
   let spot=item["spot"] as! [Double],span=item["span"] as! [Double],puff=span[2]>0.5,square=puff ? 256.0:512
   let dx=mod(spot[0]+spot[2]*drift-1480,square)-square*0.5,dy=mod(spot[1]+spot[2]*drift+1738,square)-square*0.5
   let high=160+max(0,(Double(f("z"))-200)*0.3)+30*spot[3],edge=min(1,max(abs(dx),abs(dy))/(square*0.5))
   var alpha=solid
   if puff {alpha *= 1-abs(Double(f("z"))-high)*0.004} else {if high>Double(f("z")){alpha *= 1-(high-Double(f("z")))*0.004};alpha *= min(1,max(0,abs(Double(f("z"))-high)/10))}
   if edge>0.75{alpha *= 1-(edge-0.75)*4};if puff{alpha *= min(1,max(0,(edge-0.05)*20))}
   if alpha>0{sheets.append(([1480+dx,-1738+dy,high],alpha,tint,puff ? nil:bright))}
  }
 }
 let actualSheets=actual.quads.filter {$0.texture=="cloudmasked"};assert(actualSheets.count==sheets.count)
 for (quad,reference) in zip(actualSheets,sheets){vector(quad.center,reference.0,"cloud sheet");close(quad.tint.w,reference.1,"sheet alpha");vector(SIMD3(quad.tint.x,quad.tint.y,quad.tint.z),reference.2,"sheet tint")}
 let highQuads=actual.quads.filter {$0.texture=="cloudhigh"}
 if !(vol["visible"] as! Bool){assert(highQuads.isEmpty)}
 if let rainbow=test["rainbow"] as? [String:Any]{let bow=actual.rainbow!;vector(bow.middle,native(rainbow["middle"] as! [Double]),"rainbow middle");vector(bow.across,native(rainbow["across"] as! [Double]),"rainbow across");vector(bow.over,native(rainbow["over"] as! [Double]),"rainbow over");close(bow.strength,rainbow["strength"] as! Double,"rainbow strength")}else{assert(actual.rainbow==nil)}
 if let meteor=test["meteor"] as? [String:Any]{let streak=actual.meteor!,from=native(meteor["from"] as! [Double]),along=native(meteor["along"] as! [Double]),gone=meteor["gone"] as! Double;for i in 0..<3{close(streak.head[i],Double(camera[i])+from[i]+along[i]*gone,"meteor head");close(streak.tail[i],Double(camera[i])+from[i]+along[i]*(gone+50),"meteor tail")}}else{assert(actual.meteor==nil)}
 elapsed += f("delta")
}
assert(atmosphere.isLoaded)
print("PASS: \(cases.count) archived JS sky frames, 58 sheet and 180 volume definitions; \(comparisons) native position/color/state comparisons")
'''


def main():
    chunks = ROOT / 'local-only/site/_next/static/chunks'
    game = next(p for p in chunks.glob('*.js') if 'yM=[...wD.c$,24]' in p.read_text())
    world = next(p for p in chunks.glob('*.js') if '7508:(e,t,n)' in p.read_text() and '98459:e=>' in p.read_text())
    data = ROOT / 'local-only/site/game/native/atmosphere.json'
    with tempfile.TemporaryDirectory(prefix='zgta-atmosphere-') as tmp:
        work = Path(tmp)
        js = work / 'reference.js'; js.write_text(JAVASCRIPT)
        reference = work / 'reference.json'
        subprocess.run(['node', str(js), str(game), str(data), str(world), str(reference)], check=True)
        swift = work / 'verify.swift'
        swift.write_text(''.join((ROOT / f'ios/App/{name}.swift').read_text() for name in ['ServerAddress','NativeWorldEnvironment','NativeAtmosphere']) + SWIFT)
        subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(swift),str(data),str(reference)],check=True)


if __name__ == '__main__':
    main()
