#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored original-size world resources, actual Metal mapping, independent image references."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,subprocess,sys,time
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--require-gpu',action='store_true');args=p.parse_args()
 out=ROOT/'local-only/research/world-sharp-146/gpu'/str(time.time_ns());out.mkdir(parents=True)
 names=['WorldBinary.swift','NativeWorldSharpLayout.swift','NativeWorldSharpTextures.swift','NativeWorldSharpWork.swift','NativeWorldSharpLoader.swift','ServerAddress.swift']
 files=[ROOT/'ios/App'/n for n in names]+[ROOT/'ios/App/WorldShaders.metal',ROOT/'tools/assets/prepare_native_assets.py',Path(__file__),Path(__file__).with_suffix('.swift')]
 before={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 spec=importlib.util.spec_from_file_location('world_producer',ROOT/'tools/assets/prepare_native_assets.py');producer=importlib.util.module_from_spec(spec);spec.loader.exec_module(producer)
 atlas=Image.new('RGBA',(2048,256),(255,0,255,255))
 for n in range(3):
  pixels=bytes(v for y in range(256)for x in range(256)for v in [(x*13+n*71)%256,(y*7+n*11)%256,(x+y*3+n*53)%256,(x+y+n*37)%256])
  (out/f'tile-{n}.rgba').write_bytes(pixels);atlas.paste(Image.frombytes('RGBA',(256,256),pixels),(n*256,0))
 atlas.save(out/'authored.hd.webp',lossless=True,exact=True)
 with Image.open(out/'authored.hd.webp')as encoded:assert encoded.tobytes()==atlas.tobytes(),'Authored input encoder changed transparent RGB before production conversion'
 producer.prepare_image(out/'authored.hd.webp',out/'authored.hd.png',(2048,256))
 with Image.open(out/'authored.hd.png')as actual:assert actual.tobytes()==atlas.tobytes(),'Producer altered source pixels'
 # Exercise the public CLI, sparse optional images and cache repair without
 # modifying an installed archive or borrowing an original-game test fixture.
 fixture=out/'world';fixture.mkdir()
 index=dict(tiles=[dict(name='t0')],detail=dict(cells=[dict(cell=0,sharp=3)]),inside=dict(cells=[dict(cell=0,sharp=1)]))
 (fixture/'index.json').write_text(json.dumps(index))
 for name in ['t0','c0','i0']:Image.new('RGBA',(2048,128),(17,31,47,255)).save(fixture/(name+'.webp'),lossless=True)
 (fixture/'c0.hd.webp').write_bytes((out/'authored.hd.webp').read_bytes())
 cli=[sys.executable,str(ROOT/'tools/assets/prepare_native_assets.py'),'--root',str(fixture),'--all-details']
 result=subprocess.run(cli,text=True,capture_output=True,check=True)
 assert '1 high-resolution atlases; 1 optional sources unavailable' in result.stdout
 with Image.open(fixture/'c0.hd.png')as generated:assert generated.tobytes()==atlas.tobytes()
 unchanged=(fixture/'c0.hd.png').stat().st_mtime_ns
 subprocess.run(cli,text=True,capture_output=True,check=True)
 assert (fixture/'c0.hd.png').stat().st_mtime_ns==unchanged,'Unchanged native images were rebuilt'
 (fixture/'c0.hd.png').write_bytes(b'corrupt')
 subprocess.run(cli,text=True,capture_output=True,check=True)
 with Image.open(fixture/'c0.hd.png')as repaired:assert repaired.tobytes()==atlas.tobytes()
 before_bad=(fixture/'c0.hd.png').read_bytes()
 Image.new('RGBA',(1024,256),(1,2,3,4)).save(fixture/'bad.webp',lossless=True)
 try:producer.prepare_image(fixture/'bad.webp',fixture/'c0.hd.png',(2048,256))
 except ValueError:pass
 else:raise AssertionError('Invalid sharp dimensions accepted')
 assert (fixture/'c0.hd.png').read_bytes()==before_bad,'Failed conversion replaced a valid image'
 # Reference samples a standalone 256px image, independent of the array/map.
 reference='''
fragment half4 independentSharpReference(Raster in [[stage_in]],texture2d<half> image [[texture(0)]]) {
 constexpr sampler original(coord::normalized,address::repeat,filter::linear,mip_filter::linear,max_anisotropy(4));
 half4 value=image.sample(original,in.uv);if(value.a<0.1h) discard_fragment();return value;
}
'''
 (out/'production.metal').write_text((ROOT/'ios/App/WorldShaders.metal').read_text()+reference)
 command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*[str(ROOT/'ios/App'/n)for n in names],str(Path(__file__).with_suffix('.swift')),'-o',str(out/'probe')]
 with(out/'compile.log').open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300)
 if r.returncode:print((out/'compile.log').read_text()[-8000:]);r.check_returncode()
 with(out/'runtime.log').open('w')as log:r=subprocess.run([str(out/'probe'),str(out),*(['--require-gpu']if args.require_gpu else[])],stdout=log,stderr=subprocess.STDOUT,timeout=180)
 if r.returncode:print((out/'runtime.log').read_text()[-8000:]);r.check_returncode()
 report=json.loads((out/'report.json').read_text());report.update(sourceUnchanged=all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in before.items()),sourceHashes=before,work=str(out));assert report['sourceUnchanged']
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
