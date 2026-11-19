#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual offscreen Metal atlas sampling with independently authored PNGs."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse, hashlib, json, os, re, subprocess, time
from pathlib import Path
from tests.resources.smoke_native_ped_atlas_support import family, png, digest, canonical
from tests.vehicles.smoke_native_vehicle_transparency import block

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metal', type=Path)
    parser.add_argument('--compile-only', action='store_true')
    parser.add_argument('--source-root', type=Path, default=ROOT/'ios/App', help='Explicit native source snapshot for regression comparisons; authored fixtures only.')
    args = parser.parse_args()
    native = args.source_root.resolve(strict=True)
    out = ROOT / 'local-only/research/ped-atlas-120/gpu' / str(time.time_ns())
    stage = out / 'source'; stage.mkdir(parents=True)
    fixtures = out / 'fixtures'; fixtures.mkdir()
    cases = [family('legacy', body=(128,128)), family('portrait', body=(128,256)),
             family('mixed', mixed=True), family('white', txd=False)]
    for alpha in [20,26,64,128]:
        value=family('alpha'+str(alpha), body=(8,16))
        pixels=bytearray(value['pixels'])
        for offset in range(3,len(pixels),4): pixels[offset]=alpha
        value['pixels']=bytes(pixels)
        value['files']['atlas']=png(*value['size'],bytes(pixels))
        value['layout']['atlasSHA256']=digest(value['files']['atlas'])
        cases.append(value)
    cases.extend([family('v2nearest',body=(128,256),version=2,filters=(1,)),
                  family('v2linear',body=(128,256),version=2,filters=(6,)),
                  family('v2linear2',body=(128,256),version=2,filters=(2,)),
                  family('v2mixed',mixed=True,version=2,filters=(1,6,2)),
                  family('v2white',txd=False,version=2),
                  family('v1compare'),family('v2comparelinear',version=2,filters=(6,)),
                  family('v2comparepoint',version=2,filters=(1,))])
    for alpha in [20,26,64,128]:
        value=family('v2alpha'+str(alpha),version=2,filters=(6,))
        pixels=bytearray(value['pixels']);aw,_=value['size']
        for layer in value['layout']['layers'][1:]:
            x,y,w,h=layer['rect']
            layer['sampler'].update(nativeFlags=1,rasterFormat=0x500)
            for yy in range(y,y+h):
                for xx in range(x,x+w):pixels[(yy*aw+xx)*4+3]=alpha
        value['pixels']=bytes(pixels);value['files']['atlas']=png(*value['size'],bytes(pixels))
        value['layout']['atlasSHA256']=digest(value['files']['atlas']);cases.append(value)
    descriptions=[]
    for value in cases:
        target=fixtures/value['model']; target.mkdir()
        for role in ['mesh','atlas']: (target/(role+'.data')).write_bytes(value['files'][role])
        (target/'layout.json').write_bytes(canonical(value['layout']))
        (target/'pixels.rgba').write_bytes(value['pixels'])
        aw,_=value['size']
        for layer in value['layout']['layers']:
            x,y,w,h=layer['rect']
            tile=b''.join(value['pixels'][((y+row)*aw+x)*4:((y+row)*aw+x+w)*4] for row in range(h))
            (target/('tile-'+str(layer['slot'])+'.png')).write_bytes(png(w,h,tile))
        descriptions.append(value['model'])
    (fixtures/'cases.json').write_text(json.dumps(descriptions))
    names=['NativeWorldRenderer.swift','WorldBinary.swift','NativePedAtlasLayout.swift','WorldShaders.metal','SkeletalShaders.metal','NativePedTextureArrays.swift']
    tests=['tests/resources/smoke_native_ped_atlas_gpu.py','tests/resources/smoke_native_ped_atlas_gpu.swift','tests/resources/smoke_native_ped_atlas_support.py','tests/vehicles/smoke_native_vehicle_transparency.py']
    inputs=[native/n for n in names]+[ROOT/n for n in tests]
    before={str(p.relative_to(ROOT)):digest(p.read_bytes()) for p in inputs}
    renderer=(native/'NativeWorldRenderer.swift').read_text()
    # The generic model descriptor ends before the separate world material.
    # The world-material gate executes the complete constructor independently.
    start=renderer.index('        let descriptor = MTLRenderPipelineDescriptor()')
    world_boundary=renderer.find('        descriptor.fragmentFunction = worldFragment',start)
    end=world_boundary if world_boundary>=0 else renderer.index('        descriptor.colorAttachments[0].writeMask = []',start)
    pipeline=renderer[start:end]
    ordinary=re.search(r'let fragment = library\.makeFunction\(name: "([^"]+)"\)',renderer[renderer.index('    init?(preferredDevice:'):]).group(1)
    source=(ROOT/'tests/resources/smoke_native_ped_atlas_gpu.swift').read_text().replace('// ACTUAL_UNIFORMS',block(renderer,'    private struct Uniforms {')).replace('// ACTUAL_PIPELINE',pipeline).replace('MODEL_FRAGMENT_NAME',ordinary)
    (stage/'main.swift').write_text(source)
    for name in names[1:]: (stage/name).write_bytes((native/name).read_bytes())
    world=(stage/'WorldShaders.metal').read_text()
    reference='\n\n'.join(['#include <metal_stdlib>\nusing namespace metal;',
        block(world,'struct Uniforms {')+';',block(world,'struct Raster {')+';',
        block(world,'static half4 ordinaryActorShade('),
        '''// Test-only independent oracle: an isolated original-sized texture
// and Metal's actual repeat sampler, without atlas coordinate arithmetic.
fragment half4 nativePedReferenceFragment(Raster in [[stage_in]],
    texture2d<half> image [[texture(0)]],
    constant Uniforms &uniforms [[buffer(1)]],constant float &mode [[buffer(2)]]) {
    constexpr sampler point(coord::normalized,address::repeat,filter::nearest,mip_filter::none);
    constexpr sampler linear(coord::normalized,address::repeat,filter::linear,mip_filter::none);
    half4 color=mode==1.0 ? image.sample(point,in.uv):image.sample(linear,in.uv);
    return ordinaryActorShade(in,color,uniforms);
}'''])
    (stage/'SamplerReference.metal').write_text(reference)
    compiler=args.metal
    if compiler is None:
        configured=os.environ.get('ZGTA_METAL_COMPILER')
        mounts=Path.home()/'Library/Developer/DVTDownloads/MetalToolchain/mounts'
        choices=sorted(mounts.glob('*/Metal.xctoolchain/usr/bin/metal')) if mounts.is_dir() else []
        compiler=Path(configured) if configured else choices[-1] if choices else Path(subprocess.check_output(['xcrun','--find','metal'],text=True).strip())
    commands=[]
    def run(command,label,timeout=240):
        command=['nice','-n','15',*map(str,command)]; commands.append(command)
        with (out/(label+'.log')).open('w') as log:
            result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=timeout,env={k:v for k,v in os.environ.items() if k!='SDKROOT'})
        if result.returncode: print((out/(label+'.log')).read_text()[-5000:]); result.check_returncode()
    sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    airs=[]
    for name in ['WorldShaders','SkeletalShaders','SamplerReference']:
        air=stage/(name+'.air'); airs.append(air)
        run([compiler,'-target','air64-apple-macos13.0','-isysroot',sdk,'-fmodules-cache-path='+str(out/'metal-modules'),'-c',stage/(name+'.metal'),'-o',air],'metal-'+name)
    run([compiler.with_name('metallib'),*airs,'-o',out/'production.metallib'],'link-metal')
    run(['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-swift-version','5','-module-cache-path',out/'modules',stage/'WorldBinary.swift',stage/'NativePedAtlasLayout.swift',stage/'NativePedTextureArrays.swift',stage/'main.swift','-o',out/'verify'],'swift')
    if args.compile_only:
        print(json.dumps({'status':'COMPILED_ONLY','work':str(out)})); return
    run([out/'verify',out],'runtime')
    report=json.loads((out/'gpu-report.json').read_text())
    assert all(digest((ROOT/path).read_bytes())==sha for path,sha in before.items())
    report.update(sourceHashes=before,sourceUnchanged=True,commands=commands,originalDataUsed=False,
                  metallibSHA256=digest((out/'production.metallib').read_bytes()),
                  referenceMetalSHA256=digest((stage/'SamplerReference.metal').read_bytes()))
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    (out.parent/'latest.json').write_text(json.dumps(dict(report,work=str(out)),indent=2)+'\n')
    print(json.dumps({'status':report['status'],'checks':report['checks'],'renders':report['renders'],'device':report['device'],'work':str(out)}))

if __name__=='__main__': main()
