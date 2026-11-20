#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual skinned/static material encoders and authored Metal pixel controls."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tests.resources.smoke_native_stock_ped import textured_ped,txd
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--require-gpu',action='store_true');p.add_argument('--ped-source',type=Path);a=p.parse_args()
    out=ROOT/'local-only/research/ped-materials-150'/str(time.time_ns());out.mkdir(parents=True)
    (out/'authored.dff').write_bytes(textured_ped());(out/'authored.txd').write_bytes(txd([(255,0,0,255)]*3))
    names=['NativeRenderWareDFF','NativeRenderWareTXD','NativeRenderWareModel','NativeRenderWareSkeleton','NativeRenderWarePedModel',
           'NativeActorAnimation','NativeFootAnimation','NativeGunAnimation','NativeFlightAnimation','NativeSwimAnimation','NativeRiderAnimation','NativeSkeletalActor']
    paths=[a.ped_source if n=='NativeRenderWarePedModel'and a.ped_source else ROOT/'ios/App'/(n+'.swift')for n in names]
    fixture=Path(__file__).with_suffix('.swift');paths.append(fixture)
    shaders=[ROOT/'ios/App/NativeRenderWareModel.metal',ROOT/'ios/App/NativeRenderWarePedModel.metal']
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [*paths,*shaders,Path(__file__)]}
    (out/'actual.metal').write_text('\n'.join(p.read_text()for p in shaders))
    command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths),'-o',str(out/'materials')]
    with(out/'compile.log').open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300)
    if r.returncode:print((out/'compile.log').read_text()[-6000:]);r.check_returncode()
    r=subprocess.run([str(out/'materials'),str(out),*(['--require-gpu']if a.require_gpu else[])],capture_output=True,text=True,timeout=120)
    (out/'runtime.log').write_text(r.stdout+r.stderr)
    report=dict(status=('SKIP_GPU'if r.stdout.startswith('SKIP')else'PASS')if r.returncode==0 else'FAIL',exitCode=r.returncode,output=r.stdout+r.stderr,sourceSHA256=frozen,
                sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),originalFilesUsed=False,
                scope='Production skinned/static encoders and shaders, authored rig/texture/CLP1, actual Metal readback; static rest geometry uses actual actor positions. No installed/hardware/retail claim')
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    print(json.dumps(report));r.check_returncode();assert report['sourcesHeld']
if __name__=='__main__':main()
