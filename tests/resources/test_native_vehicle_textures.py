#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored native-size vehicle image round trips and actual Metal upload/draws."""
from pathlib import Path
import argparse, base64, hashlib, importlib.util, json, os, subprocess, sys, time
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tests.vehicles.smoke_native_vehicle_transparency import block

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--require-gpu',action='store_true');args=parser.parse_args()
    out=ROOT/'local-only/research/vehicle-textures-145/authored'/str(time.time_ns());out.mkdir(parents=True)
    sources=['NativeVehicleRig.swift','NativeVehiclePaint.swift','NativeVehicleTextures.swift','WorldBinary.swift','NativeWorldRenderer.swift','WorldShaders.metal','VehicleShaders.metal','NativePreparedRuntimeVerifier.swift']
    files=[ROOT/'ios/App'/name for name in sources]+[Path(__file__),ROOT/'tests/resources/test_native_vehicle_textures.swift',ROOT/'tools/assets/prepare_native_vehicle_rig_atlas.py']
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    rows=[]
    for slot,(w,h) in enumerate([(256,64),(64,256),(3,5)]):
        rgba=bytes(v for y in range(h) for x in range(w) for v in [(x*13+slot*31)%256,(y*17+11)%256,(x+y*3+slot*47)%256,255])
        rows.append(dict(name='authored-'+str(slot),width=w,height=h,rgba=base64.b64encode(rgba).decode()))
        Image.frombytes('RGBA',(w,h),rgba).save(out/('tile-'+str(slot+1)+'.png'))
    Image.new('RGBA',(1,1),(255,255,255,255)).save(out/'tile-0.png')
    Image.new('RGBA',(1024,16),(17,31,47,255)).save(out/'short-native.png')
    script=ROOT/'tools/assets/prepare_native_vehicle_rig_atlas.py'
    result=subprocess.run([sys.executable,str(script),str(out/'atlas.png'),'--native-textures'],input=json.dumps(rows),text=True,capture_output=True,check=True)
    layout=json.loads(result.stdout);image=Image.open(out/'atlas.png').convert('RGBA');checks=0
    for row,rect in zip(rows,layout['rects'][1:]):
        x,y,w,h=rect;assert (w,h)==(row['width'],row['height']);checks+=1
        assert image.crop((x,y,x+w,y+h)).tobytes()==base64.b64decode(row['rgba']);checks+=1
    assert image.crop((0,0,1,1)).tobytes()==bytes([255]*4);checks+=1
    # Preserve the actual old behavior as evidence of information loss.
    subprocess.run([sys.executable,str(script),str(out/'legacy.png')],input=json.dumps(rows),text=True,capture_output=True,check=True)
    legacy=Image.open(out/'legacy.png').crop((128,0,256,128))
    assert legacy.size!=(rows[0]['width'],rows[0]['height']);checks+=1
    spec=importlib.util.spec_from_file_location('native_vehicle_atlas',script);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    for bad in [[dict(width=0,height=1,rgba='')],[dict(width=True,height=1,rgba='')],[dict(width=2049,height=1,rgba='')],[dict(width=2,height=2,rgba=rows[0]['rgba'])],rows*43]:
        try:module.pack_native(bad)
        except (ValueError,TypeError):checks+=1
        else:raise AssertionError('Malformed or oversized image family admitted')
    layout['samplers']=[dict(wrapS=1000,wrapT=1000,magFilter=1003,minFilter=1003,generateMipmaps=False)]*4
    (out/'layout.json').write_text(json.dumps(layout))
    renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    world=(ROOT/'ios/App/WorldShaders.metal').read_text();vehicle=(ROOT/'ios/App/VehicleShaders.metal').read_text()
    # Same production fragments and vertex code, with duplicate translation-unit
    # ABI declarations removed for Metal's source-library compiler.
    for marker in ['struct Uniforms {','struct Raster {']:vehicle=vehicle.replace(block(vehicle,marker)+';','')
    (out/'production.metal').write_text(world+'\n'+vehicle)
    start=renderer.index('        let descriptor = MTLRenderPipelineDescriptor()');end=renderer.index('        descriptor.fragmentFunction = worldFragment',start)
    test=(ROOT/'tests/resources/test_native_vehicle_textures.swift').read_text().replace('// ACTUAL_UNIFORMS',block(renderer,'    private struct Uniforms {')).replace('// ACTUAL_PIPELINE',renderer[start:end])
    (out/'main.swift').write_text(test)
    verifier=(ROOT/'ios/App/NativePreparedRuntimeVerifier.swift').read_text()
    carrier='import Foundation\nimport CoreFoundation\nimport CoreGraphics\nimport ImageIO\nimport simd\nfinal class PreparedImageProbe {\n'+block(verifier,'    enum Failure: Error, LocalizedError {')+'\n'+block(verifier,'        func integer(_ value: Any?)')+'\n'+block(verifier,'        func image(_ data: Data,')+'\n}\n'
    (out/'prepared-image.swift').write_text(carrier)
    command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*[str(ROOT/'ios/App'/n)for n in sources[:4]],str(out/'prepared-image.swift'),str(out/'main.swift'),'-o',str(out/'probe')]
    with(out/'compile.log').open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300,env={k:v for k,v in os.environ.items()if k!='SDKROOT'})
    if r.returncode:print((out/'compile.log').read_text()[-9000:]);r.check_returncode()
    with(out/'runtime.log').open('w')as log:r=subprocess.run([str(out/'probe'),str(out),*(['--require-gpu']if args.require_gpu else[])],stdout=log,stderr=subprocess.STDOUT,timeout=300)
    if r.returncode:print((out/'runtime.log').read_text()[-9000:]);r.check_returncode()
    report=json.loads((out/'report.json').read_text());report.update(imageRoundTripChecks=checks,sourceHashes=hashes,sourceUnchanged=all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items()),work=str(out),originalDataUsed=False)
    assert report['sourceUnchanged'];(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
if __name__=='__main__':main()
