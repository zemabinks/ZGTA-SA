#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Real thermal/cache/contact/controller/effect/vitals owners, authored inputs.

Optional --reference accepts a separate local callable replay; it is not shipped
with this test. GPU, real server authority and retail feel need separate checks.
"""
from pathlib import Path
import argparse,hashlib,json,os,signal,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tests.vehicles.smoke_native_vehicle_transparency import block

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reference',type=Path);args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    names=['NativeVehicleThermalEffects','NativeParticleEffects','NativeWeaponEffects','NativeOriginalWorldEffects','NativeOriginalWorldVitals']
    paths=[ROOT/'ios/App'/(n+'.swift')for n in names]+[ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'ios/App/NativeGameViewController.swift',Path(__file__),Path(__file__).with_suffix('.swift')]
    if args.reference:paths.append(args.reference.resolve())
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();frozen={str(p):sha(p)for p in paths}
    out=ROOT/'local-only/research/vehicle-fire-contact'/str(time.time_ns());out.mkdir(parents=True)
    renderer=paths[5].read_text();controller=paths[6].read_text()
    fixture=Path(__file__).with_suffix('.swift').read_text()
    fixture=fixture.replace('// ACTUAL_GETTER',block(renderer,'    var hasOriginalWorldFire:Bool'))
    fixture=fixture.replace('// ACTUAL_GAMEPLAY',block(controller,'    private func stepOriginalGameplay('))
    cache=next(line.strip()for line in renderer.splitlines()if 'vehicleThermalHot[context.token]='in line)
    fixture=fixture.replace('// ACTUAL_CACHE_PUBLICATION',cache)
    assert '// ACTUAL_'not in fixture
    report=dict(status='RUNNING',startedAt=time.time(),sourceHashes=frozen,results=[],oneHeavyJob=True,scope='Actual complete thermal/particle/weapon/effect/vitals owners, literal renderer getter/cache publication and GameVC step. Authored cache/network/UI carriers. Not GPU, live multiplayer or original retail.')
    def save():(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    def run(name,command,budget):
        row=dict(name=name,command=command,startedAt=time.time());report['results'].append(row);save()
        with(out/(name+'.log')).open('x')as log:
            process=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);report['activeOwnedProcessGroup']=process.pid;save()
            try:code=process.wait(timeout=budget)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid,signal.SIGTERM)
                try:process.wait(timeout=10)
                except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
                code=124
        row.update(exitCode=code,seconds=time.time()-row['startedAt']);report['activeOwnedProcessGroup']=None;save()
        assert code==0,(name,(out/(name+'.log')).read_text()[-3000:])
    try:
        copies=[]
        for p in paths[:5]:q=out/p.name;q.write_bytes(p.read_bytes());copies.append(str(q))
        (out/'main.swift').write_text(fixture)
        run('compile',['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*copies,str(out/'main.swift'),'-o',str(out/'gate')],600)
        run('runtime',[str(out/'gate'),*([str(args.reference.resolve())]if args.reference else[])],60)
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(completedAt=time.time(),inputsHeld=all(sha(Path(p))==h for p,h in frozen.items()));save()
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']))+'\n');print({k:v for k,v in report.items()if k not in ['sourceHashes','results']},flush=True)

if __name__=='__main__':main()
