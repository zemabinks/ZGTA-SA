#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual stock-ped CPU owner, cache lifetimes and Metal allocation admission."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys,time,zlib
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tests.resources.smoke_native_stock_ped import textured_ped,txd

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--require-gpu',action='store_true');p.add_argument('--allocation-source',type=Path,help='Actual historical allocation owner for a negative reproduction');a=p.parse_args()
    out=ROOT/'local-only/research/stock-ped-runtime-152'/str(time.time_ns());fixture=out/'fixture';fixture.mkdir(parents=True)
    payloads={name+'.dff':textured_ped()for name in ['a','b','c']};payloads['shared.txd']=txd([(255,0,0,255),(0,255,0,255),(0,0,255,255)])
    assets={}
    for name,data in payloads.items():
        (fixture/name).write_bytes(data);assets[name]=dict(path=name,bytes=len(data),crc32=zlib.crc32(data)&0xffffffff,sha256=hashlib.sha256(data).hexdigest())
    (out/'manifest.json').write_text(json.dumps(dict(schema=1,models=[dict(id=100+i,kind='ped',model=name,txd='shared',source='data/peds.ide',line=i+1)for i,name in enumerate(['a','b','c'])],parents={},assets=assets,vehicleDictionary='vehicle',vehicleGenericFirst=True)))
    names=['ServerAddress','NativeStockAssetAccess','NativeSAMPStockModels','NativeSAMPStockAssetLoader','NativeStockPedLoader','NativeStockPedRuntime','NativeStockPedAllocation',
           'NativeRenderWareDFF','NativeRenderWareTXD','NativeRenderWareModel','NativeRenderWareSkeleton','NativeRenderWarePedModel','NativeRenderWareCollision',
           'NativeActorAnimation','NativeFootAnimation','NativeGunAnimation','NativeFlightAnimation','NativeSwimAnimation','NativeRiderAnimation','NativeSkeletalActor']
    paths=[a.allocation_source if n=='NativeStockPedAllocation'and a.allocation_source else ROOT/'ios/App'/(n+'.swift')for n in names]+[Path(__file__).with_suffix('.swift')]
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [*paths,Path(__file__)]}
    command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths),'-o',str(out/'runtime')]
    with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300)
    if r.returncode:
        (out/'report.json').write_text(json.dumps(dict(status='COMPILE_FAIL',exitCode=r.returncode,sourceSHA256=hashes,
            sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())),indent=2)+'\n')
        print((out/'compile.log').read_text()[-5000:]);r.check_returncode()
    r=subprocess.run([str(out/'runtime'),str(out),*(['--require-gpu']if a.require_gpu else[])],capture_output=True,text=True,timeout=120)
    (out/'runtime.log').write_text(r.stdout+r.stderr)
    report=dict(status='PASS'if r.returncode==0 else'FAIL',exitCode=r.returncode,output=r.stdout+r.stderr,sourceSHA256=hashes,
                sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items()),originalFilesUsed=False,
                scope='Actual verified local acquisition/rig preparation, controlled pure cache upload resources, actual Metal allocation/upload/mip readback. No game registration, hardware FPS or retail claim.')
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    print(json.dumps({k:report[k]for k in ['status','exitCode','sourcesHeld']}),str(out));print((r.stdout+r.stderr)[:2200]);r.check_returncode();assert report['sourcesHeld']
if __name__=='__main__':main()
