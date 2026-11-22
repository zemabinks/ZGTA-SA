#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored range partition and literal main-frame/actor-packet coordination."""
from pathlib import Path
import hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/world-transparency-147/plan'/str(time.time_ns());out.mkdir(parents=True)
 names=['WorldBinary.swift','NativeWorldSharpLayout.swift','NativeWorldSharpManifest.swift','NativeWorldDrawPlan.swift']
 files=[ROOT/'ios/App'/n for n in names]+[Path(__file__).with_suffix('.swift'),ROOT/'ios/App/NativeWorldRenderer.swift',Path(__file__)]
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 start=renderer.index('        encoder.setDepthStencilState(depth)\n        drawWorldMeshes(matrix: matrix,encoder: encoder)');end=renderer.index('        if !indoors { drawWater(',start)
 actor_start=renderer.index('        if deferredVehicleSurfaces != nil {deferredVehicleSurfaces=transparentVehicleDraws}');actor_end=renderer.index('        let visible =',actor_start)
 carrier='''
import Foundation
import simd
final class FrameCarrier {
 var events:[String]=[],deferredWorldSurfaces:[Int]=[],deferredVehicleSurfaces:[Int]?,receivedVehicles:[Int]=[],particleDrawDelta:Double=0
 var vehicleThermalHot:[String:(position:SIMD3<Double>,time:Double)]=["old":(.zero,0)]
 let depth=1
 final class Encoder{func setDepthStencilState(_ depth:Int){}}
 func drawWorldMeshes(matrix:simd_float4x4,encoder:Encoder){events.append("world-solid");deferredWorldSurfaces=[11]}
 func drawActors(encoder:Encoder,matrix:simd_float4x4){events.append("actor-solid");let transparentVehicleDraws=[5]
 ACTUAL_ACTOR_PUBLICATION
 }
 func encodeTransparentVehicles(_ rows:[Int],encoder:Encoder){events.append("standalone-vehicle");receivedVehicles=rows}
 func drawLegacyObjects(encoder:Encoder,matrix:simd_float4x4,eye:SIMD3<Float>){events.append("legacy-solid")}
 func encodeWorldAndVehicleSurfaces(vehicles:[Int],encoder:Encoder){precondition(deferredWorldSurfaces==[11]);events.append("surface-pass");receivedVehicles=vehicles}
 func run(){let encoder=Encoder(),matrix=matrix_identity_float4x4,eye=SIMD3<Float>.zero,delta:Float=0.02
 ACTUAL_FRAME
 }
}
let frame=FrameCarrier();frame.run();precondition(frame.vehicleThermalHot.isEmpty);precondition(frame.events==["world-solid","actor-solid","legacy-solid","surface-pass"]);precondition(frame.receivedVehicles==[5] && frame.deferredVehicleSurfaces==nil && frame.deferredWorldSurfaces.isEmpty)
let standalone=FrameCarrier();standalone.drawActors(encoder:FrameCarrier.Encoder(),matrix:matrix_identity_float4x4);precondition(standalone.receivedVehicles==[5] && standalone.events==["actor-solid","standalone-vehicle"])
print("PASS actual frame phase placement and standalone/deferred actor publication")
'''.replace('ACTUAL_FRAME',renderer[start:end]).replace('ACTUAL_ACTOR_PUBLICATION',renderer[actor_start:actor_end])
 (out/'main.swift').write_text(carrier)
 stages=[]
 for label,sources in [('plan',[*(ROOT/'ios/App'/n for n in names),Path(__file__).with_suffix('.swift')]),('frame',[out/'main.swift'])]:
  command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/label)]
  with(out/(label+'-compile.log')).open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
  if r.returncode:print((out/(label+'-compile.log')).read_text()[-5000:]);r.check_returncode()
  r=subprocess.run([str(out/label)],text=True,capture_output=True,timeout=30);(out/(label+'-runtime.log')).write_text(r.stdout+r.stderr);stages.append(dict(stage=label,exitCode=r.returncode,output=r.stdout+r.stderr));r.check_returncode()
 report=dict(status='PASS',stages=stages,sourceUnchanged=all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items()),sourceHashes=hashes,scope='Authored data and unrelated frame/draw boundaries; actual production phase/publication statements executed. No GPU/game scene or retail claim.')
 assert report['sourceUnchanged'];(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
