#!/usr/bin/env python3
"""Run archived water modules and compare native region/height/normal/UV data."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),sandbox={self:{webpackChunk_N_E:[]}};
for(const file of process.argv.slice(2,4))vm.runInNewContext(fs.readFileSync(file,'utf8'),sandbox);
const modules=Object.assign({},...sandbox.self.webpackChunk_N_E.map(x=>x[1])),cache={};
function load(id){if(id===85339||id===87719)return {};if(cache[id])return cache[id].exports;const m={exports:{}};cache[id]=m;modules[id](m,m.exports,load);return m.exports}
load.d=(t,o)=>Object.entries(o).forEach(([k,v])=>Object.defineProperty(t,k,{get:v}));
const original=load(9527),render=load(45065),metadata=JSON.parse(fs.readFileSync(process.argv[4],'utf8'));
class V{set(...values){this.values=values;return this}setRGB(...v){return this.set(...v.slice(0,3))}normalize(){let n=Math.hypot(...this.values);this.values=this.values.map(x=>x/n);return this}}
const positions=metadata.regions.map(r=>[(r[0]+r[2])*.5,(r[1]+r[3])*.5]);
positions.push([0,0],[1480,-1738],[-6000,-6000],[6000,6000],[2999,2999],[-2999,-2999],[1.25,-33.5]);
for(let i=0;i<250;i++)positions.push([((i*7919)%8000)-4000,((i*3571)%8000)-4000]);
const cases=[];
for(const override of [null,[.199,.241]]){
 const wave=original.qQ(override);
 for(const time of [0,1000,2999,4096,8192,123456789]){
  const from=(time%23),to=(time*7+2)%23,blend=Math.fround(.35),rough=render.Vt(from,to,blend);
  wave.set(time,rough);wave.look(123.25,-44.5);
  for(const pos of positions){
   const normal=new V(),heights=[],height=wave.rise(pos[0],pos[1],normal),present=wave.heights(pos[0],pos[1],heights);
   cases.push({override,time,from,to,blend,pos,rough,height,normal:normal.values,heights:present?heights:null,shown:wave.shown(...pos)});
  }
 }
}
const uniforms=[];
for(const time of [0,1000,4096,8192,123456789]){
 const color=[.2,.4,.5,Math.fround(.75)],rough=.7,u={tint:new V(),alphas:new V(),shifts:new V(),waves:new V()};
 render.We(color,time,rough,u);uniforms.push({time,color,rough,alphas:u.alphas.values,shifts:u.shifts.values,waves:u.waves.values});
}
const main=fs.readFileSync(process.argv[6],'utf8'),start=main.indexOf('function(e,t,l,n,r){if(!(0,_m.ij)'),stop=main.indexOf('return!0}(o.array',start);
const core=vm.runInNewContext('('+main.slice(start,stop+'return!0}'.length)+')',{_m:original});
const grids=[];
for(const origin of [[-1600,-1780],[-2000,2000],[0,-3000],[4000,4000],[1480,-1738]]){
 const data=new Float32Array(280900),wave=original.qQ(),ground=(x,y)=>x<origin[0]+10&&y<origin[1]+10?5+.001*x+.002*y:null;
 const present=core(data,ground,wave,...origin);grids.push({origin,present,values:present?Array.from(data):[]});
}
fs.writeFileSync(process.argv[5],JSON.stringify({cases,uniforms,grids}));
'''
SWIFT=r'''
let metadata=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
let normalWave=try NativeWaterWaves(data:metadata),overrideWave=try NativeWaterWaves(data:metadata,amplitudes:SIMD2(0.199,0.241))
var comparisons=0,largest:Float=0
func close(_ actual:Float,_ expected:Double,_ name:String){comparisons += 1;largest=max(largest,abs(actual-Float(expected)));assert(abs(actual-Float(expected))<0.0002,"\(name): \(actual) != \(expected)")}
for item in fixture["cases"] as! [[String:Any]]{
 let wave=item["override"] is NSNull ? normalWave:overrideWave
 let from=item["from"] as! Int,to=item["to"] as! Int,blend=(item["blend"] as! NSNumber).floatValue
 let rough=wave.weatherRoughness(from:from,to:to,blend:blend);close(rough,item["rough"] as! Double,"rough")
 wave.set(timeMilliseconds:item["time"] as! Double,roughness:rough);wave.look(x:123.25,y:-44.5)
 let pos=item["pos"] as! [Double],x=Float(pos[0]),y=Float(pos[1]),sample=wave.rise(x:x,y:y)
 close(sample.height,item["height"] as! Double,"height")
 let normal=item["normal"] as! [Double]
 for (i,j) in [(0,0),(1,2),(2,1)] {close(sample.normal[i],normal[j]*(i==1 ? -1:1),"normal")}
 if let heights=item["heights"] as? [Double]{let h=wave.heights(x:x,y:y)!;close(h.x,heights[0],"amplitude1");close(h.y,heights[1],"amplitude2")}else{assert(wave.heights(x:x,y:y)==nil)}
 close(wave.shown(x:x,y:y),item["shown"] as! Double,"shown")
}
for item in fixture["uniforms"] as! [[String:Any]]{
 let time=item["time"] as! Double,color=item["color"] as! [Double]
 normalWave.set(timeMilliseconds:time,roughness:Float(item["rough"] as! Double))
 let value=normalWave.renderUniforms(timeMilliseconds:time,color:SIMD4(Float(color[0]),Float(color[1]),Float(color[2]),Float(color[3])))
 for (name,values) in [("shifts",value.shifts),("waves",value.waves)]{let expected=item[name] as! [Double];for i in 0..<4{close(values[i],expected[i],name)}}
 let alpha=item["alphas"] as! [Double];close(value.alphas.x,alpha[0],"alpha1");close(value.alphas.y,alpha[1],"alpha2")
}
for item in fixture["grids"] as! [[String:Any]] {
 let wave=try NativeWaterWaves(data:metadata),origin=item["origin"] as! [Double]
 let gridOrigin=SIMD2<Float>(Float(origin[0]),Float(origin[1]))
 let ground:(Float,Float)->Float? = { x,y in
  guard x < Float(origin[0]+10),y < Float(origin[1]+10) else {return nil}
  let height:Double = 5+0.001*Double(x)+0.002*Double(y)
  return Float(height)
 }
 let values=wave.nearGrid(origin:gridOrigin,ground:ground)
 assert((values != nil)==item["present"] as! Bool)
 if let values {let reference=item["values"] as! [Double];assert(reference.count==values.count*4);for i in values.indices{for axis in 0..<4{close(values[i][axis],reference[i*4+axis],"near net")}}}
}
print("PASS: \((fixture["cases"] as! [Any]).count) archived JS water samples, region amplitudes, normals, distance fades and texture uniforms; \(comparisons) comparisons; max error \(largest)")
'''


def main():
    chunks=ROOT/'local-only/site/_next/static/chunks'
    files=[next(p for p in chunks.glob('*.js') if marker in p.read_text()) for marker in ['9527:(e,t,l)','45065:(e,t,a)']]
    data=ROOT/'local-only/site/game/native/water-waves.json'
    with tempfile.TemporaryDirectory(prefix='zgta-water-waves-') as tmp:
        work=Path(tmp);js=work/'reference.js';js.write_text(JS);reference=work/'reference.json'
        subprocess.run(['node',str(js),*map(str,files),str(data),str(reference),str(next(p for p in chunks.glob('*.js') if 'function(e,t,l,n,r){if(!(0,_m.ij)' in p.read_text()))],check=True)
        swift=work/'verify.swift';swift.write_text(''.join((ROOT/f'ios/App/{n}.swift').read_text() for n in ['ServerAddress','NativeWaterWaves'])+SWIFT)
        subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(swift),str(data),str(reference)],check=True)


if __name__=='__main__':main()
