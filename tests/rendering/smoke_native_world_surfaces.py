#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual world phase/range encoders, mixed vehicle ownership and authored Metal pixels."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from tests.vehicles.smoke_native_vehicle_transparency import block

def main():
 p=argparse.ArgumentParser();p.add_argument('--require-gpu',action='store_true');args=p.parse_args()
 out=ROOT/'local-only/research/world-transparency-147/gpu'/str(time.time_ns());out.mkdir(parents=True)
 names=['WorldBinary.swift','NativeWorldSharpLayout.swift','NativeWorldSharpManifest.swift','NativeWorldSharpTextures.swift','NativeWorldDrawPlan.swift']
 files=[ROOT/'ios/App'/n for n in names]+[ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'ios/App/WorldShaders.metal',ROOT/'ios/App/NativeVehicleRig.swift',Path(__file__),Path(__file__).with_suffix('.swift')]
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text();rig=(ROOT/'ios/App/NativeVehicleRig.swift').read_text();source=Path(__file__).with_suffix('.swift').read_text()
 markers={'ACTUAL_UNIFORMS':'    private struct Uniforms {','ACTUAL_MESH':'    private struct Mesh {','ACTUAL_VEHICLE_PACKET':'    private struct TransparentVehicleDraw {','ACTUAL_WORLD_PACKET':'    private struct TransparentWorldDraw {','ACTUAL_BASE':'    private struct WorldSharpBase {','ACTUAL_STAGE':'    private func stageWorldSurface(','ACTUAL_ENCODE_WORLD':'    @discardableResult private func encodeWorldSurface(','ACTUAL_ENCODE_SCENE':'    private func encodeWorldAndVehicleSurfaces(','ACTUAL_ENCODE_VEHICLE':'    private func encodeTransparentVehicles('}
 for marker,begin in markers.items():source=source.replace('// '+marker+'\n',block(renderer,begin)+'\n')
 for marker,begin in [('ACTUAL_SORT','    static func farToNear('),('ACTUAL_DEPTH','    static func projectedDepth(')]:source=source.replace('// '+marker+'\n',block(rig,begin)+'\n')
 a=renderer.index('        let descriptor = MTLRenderPipelineDescriptor()');b=renderer.index('        descriptor.fragmentFunction = worldFragment',a);source=source.replace('// ACTUAL_DESCRIPTOR',renderer[a:b])
 a=renderer.index('        var worldSurfacePipelines:');b=renderer.index('        descriptor.colorAttachments[0].isBlendingEnabled=true',a);source=source.replace('// ACTUAL_SURFACE_PIPELINES',renderer[a:b])
 a=renderer.index('        let depthDescriptor = MTLDepthStencilDescriptor()');b=renderer.index('        self.view = view',a);source=source.replace('// ACTUAL_DEPTH_STATES',renderer[a:b])
 (out/'main.swift').write_text(source)
 shader=(ROOT/'ios/App/WorldShaders.metal').read_text()+'''\nfragment half4 vehiclePaintABIProbe(Raster in [[stage_in]],constant float4 &paint [[buffer(3)]]) {return half4(paint);}\n'''
 (out/'production.metal').write_text(shader)
 command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*[str(ROOT/'ios/App'/n)for n in names],str(out/'main.swift'),'-o',str(out/'probe')]
 with(out/'compile.log').open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300)
 if r.returncode:print((out/'compile.log').read_text()[-9000:]);r.check_returncode()
 with(out/'runtime.log').open('w')as log:r=subprocess.run([str(out/'probe'),str(out),*(['--require-gpu']if args.require_gpu else[])],stdout=log,stderr=subprocess.STDOUT,timeout=180)
 if r.returncode:print((out/'runtime.log').read_text()[-9000:]);r.check_returncode()
 result=json.loads((out/'report.json').read_text());result.update(sourceUnchanged=all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items()),sourceHashes=hashes,work=str(out));assert result['sourceUnchanged']
 (out/'report.json').write_text(json.dumps(result,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
