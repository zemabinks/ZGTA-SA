#!/usr/bin/env python3
"""Compile every native atmosphere pipeline and verify GPU water displacement.

Requires local GPU access (run outside the process sandbox). Expected heights
come from executing the archived client's actual 9527 wave/shown methods.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),sandbox={self:{webpackChunk_N_E:[]}};
for(const file of process.argv.slice(2,4))vm.runInNewContext(fs.readFileSync(file,'utf8'),sandbox);
const modules=Object.assign({},...sandbox.self.webpackChunk_N_E.map(x=>x[1])),cache={};
function load(id){if(id===85339||id===87719)return {};if(cache[id])return cache[id].exports;const m={exports:{}};cache[id]=m;modules[id](m,m.exports,load);return m.exports}
load.d=(t,o)=>Object.entries(o).forEach(([k,v])=>Object.defineProperty(t,k,{get:v}));
const wave=load(9527).qQ([Math.fround(.199),Math.fround(.241)]),cases=[];wave.look(2300,-1700);
for(const time of [0,1000,2999,4096,8192,123456789])for(const rough of [.3,.55,1]){
 wave.set(time,Math.fround(rough));const positions=[];
 for(let i=0;i<400;i++){let x=2300+((i*173)%240)*.5-60,y=-1700+((i*137)%240)*.5-60;positions.push({x,y,height:5+wave.shown(x,y)})}
 cases.push({time,rough:Math.fround(rough),positions});
}
fs.writeFileSync(process.argv[4],JSON.stringify(cases));
'''
PROBE=r'''
kernel void nativeWaterProbe(const device AtmosphereVertex *vertices [[buffer(0)]],constant WaterUniforms &u [[buffer(1)]],device float4 *out [[buffer(2)]],uint id [[thread_position_in_grid]]) {
    WaterRaster value=waterVertex(vertices[id],u);out[id]=float4(value.place,value.shade.x);
}
'''
SWIFT=r'''
import Metal
struct ProbeVertex {var position:SIMD4<Float>;var uvLayer:SIMD4<Float>;var tint:SIMD4<Float>;var dusk:SIMD4<Float>}
guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else{fatalError("Metal device unavailable; run with GPU access")}
let source=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
let library=try device.makeLibrary(source:source,options:nil)
for (vertex,fragment) in [("nativeDomeVertex","nativeDomeFragment"),("nativeAtmosphereVertex","nativeSkySpriteFragment"),("nativeAtmosphereVertex","nativeCloudSpriteFragment"),("nativeAtmosphereVertex","nativeWeatherSpriteFragment"),("nativeAtmosphereVertex","nativeAtmosphereColorFragment"),("nativeAtmosphereVertex","nativeRainbowFragment"),("nativeWaterVertex","nativeWaterFragment")]{
 let descriptor=MTLRenderPipelineDescriptor();descriptor.vertexFunction=library.makeFunction(name:vertex);descriptor.fragmentFunction=library.makeFunction(name:fragment);descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm;descriptor.depthAttachmentPixelFormat = .depth32Float
 _=try device.makeRenderPipelineState(descriptor:descriptor)
}
let pipeline=try device.makeComputePipelineState(function:library.makeFunction(name:"nativeWaterProbe")!)
let metadata=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])),wave=try NativeWaterWaves(data:metadata)
let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3]))) as! [[String:Any]]
var largest:Float=0,count=0
for item in cases{
 let time=item["time"] as! Double,rough=(item["rough"] as! NSNumber).floatValue
 wave.set(timeMilliseconds:time,roughness:rough)
 let render=wave.renderUniforms(timeMilliseconds:time,color:SIMD4(0.2,0.4,0.5,0.75)),x=wave.xFactors,y=wave.yFactors
 var uniforms=WaterUniforms(matrix:matrix_identity_float4x4,eye:SIMD4(2300,-1700,13,1),tint:render.tint,alphas:SIMD4(render.alphas.x,render.alphas.y,0,0),shifts:render.shifts,waves:SIMD4(render.waves.x,render.waves.y,render.waves.z,rough),fogColor:.zero,fog:.zero,net:.zero,alongX0:SIMD4(x[0],x[1],x[2],x[3]),alongX1:SIMD4(x[4],x[5],x[6],x[7]),alongY0:SIMD4(y[0],y[1],y[2],y[3]),alongY1:SIMD4(y[4],y[5],y[6],y[7]))
 let positions=item["positions"] as! [[String:Double]]
 let vertices=positions.map {ProbeVertex(position:SIMD4(Float($0["x"]!),Float($0["y"]!),5,1),uvLayer:SIMD4(0.199,0.241,1,1),tint:.zero,dusk:.zero)}
 let input=device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<ProbeVertex>.stride)!,output=device.makeBuffer(length:vertices.count*16,options:.storageModeShared)!
 let command=queue.makeCommandBuffer()!,encoder=command.makeComputeCommandEncoder()!
 encoder.setComputePipelineState(pipeline);encoder.setBuffer(input,offset:0,index:0);encoder.setBytes(&uniforms,length:MemoryLayout<WaterUniforms>.stride,index:1);encoder.setBuffer(output,offset:0,index:2)
 encoder.dispatchThreads(MTLSize(width:vertices.count,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:64,height:1,depth:1));encoder.endEncoding();command.commit();command.waitUntilCompleted()
 assert(command.status == .completed,"GPU failure \(String(describing:command.error))")
 let values=output.contents().bindMemory(to:SIMD4<Float>.self,capacity:vertices.count)
 for i in vertices.indices{let error=abs(values[i].z-Float(positions[i]["height"]!));largest=max(largest,error);assert(error<0.001,"GPU water mismatch \(values[i].z) != \(positions[i]["height"]!)");count += 1}
}
print("PASS: all 7 native sky/weather/water Metal pipelines, \(count) GPU wave vertices match archived JS; max height error \(largest)m on \(device.name)")
'''

def main():
 chunks=ROOT/'local-only/site/_next/static/chunks'
 files=[next(p for p in chunks.glob('*.js') if m in p.read_text()) for m in ['9527:(e,t,l)','45065:(e,t,a)']]
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 uniforms=re.search(r'    private struct WaterUniforms \{.+?\n    \}',renderer,re.S).group(0).replace('private struct','struct')
 with tempfile.TemporaryDirectory(prefix='zgta-atmosphere-metal-') as tmp:
  work=Path(tmp);js=work/'reference.js';js.write_text(JS);reference=work/'reference.json'
  subprocess.run(['node',str(js),*map(str,files),str(reference)],check=True)
  metal=work/'probe.metal';metal.write_text((ROOT/'ios/App/NativeAtmosphereShaders.metal').read_text()+PROBE)
  swift=work/'verify.swift';swift.write_text(''.join((ROOT/f'ios/App/{n}.swift').read_text() for n in ['ServerAddress','NativeWaterWaves'])+uniforms+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(swift),str(metal),str(ROOT/'local-only/site/game/native/water-waves.json'),str(reference)],check=True)
if __name__=='__main__':main()
