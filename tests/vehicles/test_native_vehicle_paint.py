#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Owner-local primary oracle + actual Rig/Renderer carrier + desktop Metal.

Run the producer with --prepare after installing the owner's archived inputs.
No archive, generated geometry, texture, palette or reference is published.
The Renderer carrier extracts the actual frozen methods and uses explicit
encoder spies only for state selection; the shader is independently drawn by
the real Metal device in test_native_vehicle_paint.swift.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse, hashlib, json, pathlib, subprocess

ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/vehicle-paint-105'

def block(source, marker):
    at=source.index(marker); start=source.index('{',at); depth=1; end=start+1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}'); end+=1
    return source[at:end]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--prepare',action='store_true');parser.add_argument('--compile-only',action='store_true');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    if args.prepare:
        with (OUT/'producer.log').open('w') as log:
            subprocess.run(['node',str(ROOT/'tests/vehicles/test_native_vehicle_paint.js')],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1200)
    if not args.compile_only and not (OUT/'reference.json').is_file():
        raise SystemExit('Owner-local reference missing. Run tests/vehicles/test_native_vehicle_paint.py --prepare with the archived assets present.')
    renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    appearance=block(renderer,'private var ownVehicleAppearanceCode:String')
    draw=block(renderer,'for part in frame.draws {')
    # No replacement implementation: these two blocks are the current App's
    # source. The surrounding minimal record types only expose their boundary.
    carrier='''// Generated locally; source blocks extracted from actual Renderer.
import Foundation
import simd
import Metal
private struct PaintVehicleRow {let id:String;let code:String}
private final class PaintAppearanceCarrier {
 var currentVehicleID:String?,remoteVehicles=[PaintVehicleRow](),activeVehicleModel=""
 var ownedVehicleAppearance:(id:String,code:String)?
 APPEARANCE
 func selected()->String{ownVehicleAppearanceCode}
}
private struct PaintCarrierUniforms {var viewProjection=matrix_identity_float4x4}
private final class PaintEncoderSpy {
 var paints=[SIMD4<Float>](),materials=[SIMD4<Float>](),draws=[(Int,Int)](),vertexUniforms=0,fragmentUniforms=0
 func setVertexBytes<T>(_ value:inout T,length:Int,index:Int){VehiclePaintTest.check(index==1,"Unexpected vertex binding");vertexUniforms+=1}
 func setFragmentBytes<T>(_ value:inout T,length:Int,index:Int){
   if index==1{fragmentUniforms+=1;return}
   VehiclePaintTest.check(length==16,"Unexpected material binding size")
   let vector=withUnsafeBytes(of:&value){$0.loadUnaligned(as:SIMD4<Float>.self)}
   if index==2{materials.append(vector)}else if index==3{paints.append(vector)}else{fatalError("Unexpected fragment slot")}
 }
 func drawIndexedPrimitives(type:MTLPrimitiveType,indexCount:Int,indexType:MTLIndexType,indexBuffer:Int,indexBufferOffset:Int){draws.append((indexCount,indexBufferOffset))}
}
extension VehiclePaintTest {
 static func rendererSource(_ rig:NativeVehicleRig) {
   let owner=PaintAppearanceCarrier();owner.currentVehicleID="own";owner.activeVehicleModel="420"
   check(owner.selected()=="420","Own default model lost")
   owner.ownedVehicleAppearance=("previous","420.1.6.0.");check(owner.selected()=="420","Cross-ID cached paint leaked")
   owner.ownedVehicleAppearance=("own","420.6.1.0.");check(owner.selected()=="420.6.1.0.","Captured entry code lost")
   owner.remoteVehicles=[PaintVehicleRow(id:"other",code:"420.0.0.0."),PaintVehicleRow(id:"own",code:"420.33488896.1.0.")]
   check(owner.selected()=="420.33488896.1.0.","Fresh authoritative appearance ignored")
   owner.currentVehicleID=nil;check(owner.selected()=="420","Exited appearance leaked")
   typealias Uniforms=PaintCarrierUniforms
   let encoder=PaintEncoderSpy(),matrix=matrix_identity_float4x4,transform=matrix_identity_float4x4
   var uniforms=Uniforms(),input=NativeVehicleRig.Input(),state=NativeVehicleRig.State();input.appearanceCode="420.6.1.0."
   let frame=rig.pose(input,state:&state,delta:1/60),mesh=(indices:0,unused:0)
   DRAW
   check(encoder.draws.count==frame.draws.count&&encoder.paints==frame.draws.map(\\.paint),"Actual Renderer omitted or shared per-part paint")
   check(encoder.vertexUniforms==frame.draws.count&&encoder.fragmentUniforms==frame.draws.count,"Per-part fragment camera/alpha uniforms lost")
   for (index,part) in frame.draws.enumerated(){check(encoder.draws[index].0==part.count&&encoder.draws[index].1==part.start*4,"Actual draw offset changed")}
 }
}
'''.replace('APPEARANCE',appearance).replace('DRAW',draw)
    carrierPath=OUT/'renderer-carrier.swift';carrierPath.write_text(carrier)
    files=[ROOT/'ios/App'/name for name in ['NativeVehiclePaint.swift','NativeVehicleRig.swift','WorldBinary.swift']]+[ROOT/'tests/vehicles/test_native_vehicle_paint.swift',carrierPath]
    hashed=files+[ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'ios/App/VehicleShaders.metal',ROOT/'tools/assets/prepare_native_vehicle_rigs.js',ROOT/'tests/vehicles/test_native_vehicle_paint.js',pathlib.Path(__file__)]
    before={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in hashed}
    subprocess.run(['swiftc','-O',*[str(p) for p in files],'-module-cache-path',str(OUT/'modules'),'-o',str(OUT/'paint-tests')],cwd=ROOT,check=True,timeout=180)
    if args.compile_only:
        print('PASS: actual paint sources and Renderer carrier compile');return
    with (OUT/'runtime.log').open('w') as log:
        subprocess.run([str(OUT/'paint-tests'),str(ROOT)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
    after={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in hashed}
    if before!=after:raise SystemExit('Source changed during vehicle paint acceptance')
    (OUT/'source-hashes.json').write_text(json.dumps(after,indent=2)+'\n')
    print((OUT/'runtime-report.json').read_text())

if __name__=='__main__':main()
