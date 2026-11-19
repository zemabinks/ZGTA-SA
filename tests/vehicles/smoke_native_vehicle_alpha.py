#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual offscreen desktop Metal with authored geometry; no owner files/UI."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse,hashlib,json,os,struct,subprocess,time,zlib
from pathlib import Path
from tests.vehicles.smoke_native_vehicle_transparency import block
ROOT=Path(__file__).resolve().parents[2]

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--metal',type=Path);parser.add_argument('--compile-only',action='store_true');args=parser.parse_args()
 out=ROOT/'local-only/research/vehicle-alpha-authored-110'/str(time.time_ns());stage=out/'source';stage.mkdir(parents=True)
 compiler=args.metal
 if compiler is None:
  configured=os.environ.get('ZGTA_METAL_COMPILER');mounts=Path.home()/'Library/Developer/DVTDownloads/MetalToolchain/mounts'
  available=sorted(mounts.glob('*/Metal.xctoolchain/usr/bin/metal'))if mounts.is_dir()else[]
  compiler=Path(configured)if configured else available[-1]if available else Path(subprocess.check_output(['xcrun','--find','metal'],text=True).strip())
 names=['NativeWorldRenderer.swift','NativeVehicleRig.swift','NativeVehiclePaint.swift','WorldShaders.metal','VehicleShaders.metal','SkeletalShaders.metal']
 files=[ROOT/'ios/App'/n for n in names]+[Path(__file__),ROOT/'tests/vehicles/smoke_native_vehicle_alpha.swift',ROOT/'tests/vehicles/smoke_native_vehicle_transparency.py']
 before={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 for n in names:(stage/n).write_bytes((ROOT/'ios/App'/n).read_bytes())
 renderer=(stage/'NativeWorldRenderer.swift').read_text()
 pipeline=renderer[renderer.index('        let descriptor = MTLRenderPipelineDescriptor()'):renderer.index('        descriptor.colorAttachments[0].writeMask = []')]
 depth=renderer[renderer.index('        let depthDescriptor = MTLDepthStencilDescriptor()'):renderer.index('        self.view = view',renderer.index('        let depthDescriptor ='))]
 source=(ROOT/'tests/vehicles/smoke_native_vehicle_alpha.swift').read_text().replace('// ACTUAL_UNIFORMS',block(renderer,'    private struct Uniforms {')).replace('// ACTUAL_PIPELINE',pipeline).replace('// ACTUAL_DEPTH',depth).replace('// ACTUAL_DEFERRED_ENCODER',block(renderer,'    private func encodeTransparentVehicles('))
 (stage/'main.swift').write_text(source)
 def run(command,label):
  with(out/(label+'.log')).open('w')as log:r=subprocess.run(list(map(str,command)),stdout=log,stderr=subprocess.STDOUT,env={k:v for k,v in os.environ.items()if k!='SDKROOT'},timeout=600)
  if r.returncode:print((out/(label+'.log')).read_text()[-6000:]);r.check_returncode()
 sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip();airs=[]
 for name in ['WorldShaders','VehicleShaders','SkeletalShaders']:
  air=stage/(name+'.air');run([compiler,'-target','air64-apple-macos13.0','-isysroot',sdk,'-fmodules-cache-path='+str(out/'metal-modules'),'-c',stage/(name+'.metal'),'-o',air],'compile-'+name);airs.append(air)
 run([compiler.with_name('metallib'),*airs,'-o',out/'production.metallib'],'link-metal')
 run(['xcrun','swiftc','-whole-module-optimization','-Onone','-module-cache-path',out/'swift-modules',stage/'NativeVehicleRig.swift',stage/'NativeVehiclePaint.swift',stage/'main.swift','-o',out/'probe'],'compile-swift')
 if args.compile_only:print(json.dumps({'status':'COMPILED_ONLY_NOT_RUNTIME_ACCEPTED','work':str(out)}));return
 run([out/'probe',ROOT,out],'runtime')
 report=json.loads((out/'gpu-report.json').read_text());assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==sha for p,sha in before.items())
 report.update(sourceHashes=before,sourceUnchanged=True,originalDataUsed=False,metallibSHA256=hashlib.sha256((out/'production.metallib').read_bytes()).hexdigest())
 for p in out.glob('*.bgra'):
  raw=p.read_bytes();w,h=128,96;rgba=bytes(raw[i+j]for i in range(0,len(raw),4)for j in [2,1,0,3]);rows=b''.join(b'\0'+rgba[y*w*4:(y+1)*w*4]for y in range(h))
  def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
  p.with_suffix('.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'checks':report['checks'],'actualDeferredEncoderExtracted':True,'work':str(out)}))
if __name__=='__main__':main()
