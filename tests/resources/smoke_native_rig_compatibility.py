#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Real SKN1 rig/skin admission, constructor validation and optional original pairs."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys,time,zlib
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tests.resources.smoke_native_stock_ped import textured_ped,txd

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--require-gpu',action='store_true');p.add_argument('--owner-model',action='append',default=[]);p.add_argument('--stock-catalog',type=Path);a=p.parse_args()
    out=ROOT/'local-only/research/rig-compatibility-152'/str(time.time_ns());files=out/'files';files.mkdir(parents=True)
    assets={};models=[dict(id=19999,kind='ped',model='authored',txd='authored',source='data/authored.ide',line=1)];parents={};cases=[];original={}
    def asset(name,data):
        (files/name).write_bytes(data);assets[name]=dict(path=name,bytes=len(data),crc32=zlib.crc32(data)&0xffffffff,sha256=hashlib.sha256(data).hexdigest())
    asset('authored.dff',textured_ped());asset('authored.txd',txd([(255,0,0,255)]*3))
    if a.owner_model:
        assert a.stock_catalog and len(a.owner_model)<=16 and len(set(a.owner_model))==len(a.owner_model)
        assert all(re.fullmatch('[a-z0-9_]{1,40}',name)for name in a.owner_model)
        catalog=json.loads(a.stock_catalog.read_text());game=ROOT/'local-only/site/game'
        for name in a.owner_model:
            rows=[r for r in catalog['models']if r['kind']=='ped'and r['model']==name];assert len(rows)==1;row=rows[0];assert row['id']!=19999
            models.append(row);names=[name+'.dff'];seen=[];dictionary=row['txd']
            while dictionary:
                assert dictionary not in seen and len(seen)<32;seen.append(dictionary);names.append(dictionary+'.txd');parent=catalog['parents'].get(dictionary)
                if parent:parents[dictionary]=parent
                dictionary=parent
            for member in names:
                source=(game/member).resolve(strict=True);raw=source.read_bytes();original[str(source)]=hashlib.sha256(raw).hexdigest()
                target=files/member
                if not target.exists():subprocess.run(['cp','-c',str(source),str(target)],check=True)
                assert not target.is_symlink()and hashlib.sha256(target.read_bytes()).hexdigest()==original[str(source)]
                assets[member]=dict(path=member,bytes=len(raw),crc32=zlib.crc32(raw)&0xffffffff,sha256=original[str(source)])
            skeleton=(game/'native/models'/(name+'.skel.bin')).resolve(strict=True);original[str(skeleton)]=hashlib.sha256(skeleton.read_bytes()).hexdigest()
            cases.append(dict(id=row['id'],name=name,skeleton=str(skeleton)))
    (out/'manifest.json').write_text(json.dumps(dict(schema=1,models=models,parents=parents,assets=assets,vehicleDictionary='vehicle',vehicleGenericFirst=True)))
    (out/'owner-cases.json').write_text(json.dumps(cases))
    names=['ServerAddress','NativeStockAssetAccess','NativeSAMPStockModels','NativeSAMPStockAssetLoader','NativeStockPedLoader','NativeStockPedAllocation',
           'NativeRenderWareDFF','NativeRenderWareTXD','NativeRenderWareModel','NativeRenderWareSkeleton','NativeRenderWarePedModel','NativeRenderWareCollision',
           'NativeActorAnimation','NativeFootAnimation','NativeGunAnimation','NativeFlightAnimation','NativeSwimAnimation','NativeRiderAnimation','NativeSkeletalActor']
    paths=[ROOT/'ios/App'/(n+'.swift')for n in names]+[Path(__file__).with_suffix('.swift')];frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [*paths,Path(__file__)]}
    cmd=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths),'-o',str(out/'rigs')]
    with(out/'compile.log').open('x')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=300)
    if r.returncode:
        (out/'report.json').write_text(json.dumps(dict(status='COMPILE_FAIL',exitCode=r.returncode,sourceSHA256=frozen),indent=2)+'\n');print((out/'compile.log').read_text()[-5000:]);r.check_returncode()
    r=subprocess.run([str(out/'rigs'),str(out),*(['--require-gpu']if a.require_gpu else[])],capture_output=True,text=True,timeout=180)
    (out/'runtime.log').write_text(r.stdout+r.stderr)
    report=dict(status=('SKIP_GPU'if r.stdout.startswith('SKIP')else'PASS')if r.returncode==0 else'FAIL',exitCode=r.returncode,output=r.stdout+r.stderr,
                sourceSHA256=frozen,sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),
                ownerModels=a.owner_model,ownerInputsHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in original.items()),ownerSourceSHA256=original,
                scope='Actual verified file/rig pipeline, native SKN1 actors, equal-count incompatible-rig controls and validation before material upload. Original pairs optional/local; no game/retail claim.')
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    print(json.dumps({k:report[k]for k in ['status','exitCode','sourcesHeld','ownerInputsHeld']}),str(out));print((r.stdout+r.stderr)[:1800]);r.check_returncode();assert report['sourcesHeld']and report['ownerInputsHeld']
if __name__=='__main__':main()
