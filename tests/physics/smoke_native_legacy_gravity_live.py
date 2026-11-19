#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Owned loopback open.mp -> actual native renderer/physics gravity acceptance.

Requires the existing official QA image and locally built host bridges.
No original game data, browser, phone or public server is used.
"""
from pathlib import Path
import hashlib
import json
import math
import os
import platform
import subprocess
import sys
import time
import uuid

ROOT=Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from tests.network.smoke_samp_controls import NAMES as NETWORK_NAMES,BASE
from tests.vehicles.smoke_native_parked_phase import NAMES as PHYSICS_NAMES
from tests.resources.smoke_native_actor_selection import extract

def main():
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/legacy-gravity-144/live'/str(time.time_ns());work=out/'source';work.mkdir(parents=True);work.chmod(0o777)
    names=list(dict.fromkeys(NETWORK_NAMES+PHYSICS_NAMES+['NativeSAMPGameCamera','NativeCharacterMotor','NativeCharacterController','NativeRapierCharacterQueries']))
    fixtures=[Path(__file__),Path(__file__).with_suffix('.swift'),Path(__file__).with_suffix('.pwn'),ROOT/'tests/physics/smoke_native_legacy_gravity.swift',ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'ios/App/NativeActorAnimation.swift']
    files=[ROOT/'ios/App'/(name+'.swift') for name in names]+fixtures
    captured={p:p.read_bytes() for p in files}
    sha=lambda raw:hashlib.sha256(raw).hexdigest()
    renderer=captured[ROOT/'ios/App/NativeWorldRenderer.swift'].decode()
    helper=captured[ROOT/'tests/physics/smoke_native_legacy_gravity.swift'].decode().split('@main private struct GravityGate {')[0]
    helper=helper.replace('// ACTUAL_RECEIVE_LEGACY_GAMEPLAY',extract(renderer,'    func receiveLegacyGameplay('))
    helper=helper.replace('// ACTUAL_FALLBACK_BRANCH',extract(renderer,'else if !driving && (verticalSpeed != 0 || (legacyGravity ?? 0)<0)'))
    (work/'Gate.swift').write_text(helper+'\n'+captured[Path(__file__).with_suffix('.swift')].decode())
    actor=captured[ROOT/'ios/App/NativeActorAnimation.swift'].decode()
    motion=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
    (work/'Motion.swift').write_text('import Foundation\nimport simd\n'+motion)
    for name in names:(work/(name+'.swift')).write_bytes(captured[ROOT/'ios/App'/(name+'.swift')])
    native=ROOT/('local-only/native-physics/macos-'+platform.machine())
    samp=ROOT/('local-only/native-samp/macos-'+platform.machine())
    subprocess.run(['python3','native-physics/source_stamp.py','check',str(native)],cwd=ROOT,check=True)
    frozen_bridges={p:sha(p.read_bytes()) for p in [native/'libzgtasa_native_physics.a',samp/'libzgtasa_samp.a']}
    command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone',
             '-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),'-I',str(ROOT/'native-samp/include'),
             *[str(work/(n+'.swift')) for n in names],str(work/'Motion.swift'),str(work/'Gate.swift'),
             '-L',str(native),'-L',str(samp),'-lzgtasa_native_physics','-lzgtasa_samp','-lresolv',
             '-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
    with (out/'swift-build.log').open('w')as log:built=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=600)
    if built.returncode:print((out/'swift-build.log').read_text()[-6000:]);built.check_returncode()
    (work/'fixture.pwn').write_bytes(captured[Path(__file__).with_suffix('.pwn')])
    base=json.loads(subprocess.check_output(['docker','image','inspect',BASE,'--format','{{json .}}'],text=True))
    image='zgtasa-gravity144-qa:'+uuid.uuid4().hex[:12];name='zgtasa-gravity144-'+uuid.uuid4().hex[:12]
    created=False
    try:
        compiler=['docker','run','--rm','--pull=never','--network=none','--cpus=0.5','--memory=256m','--entrypoint','/bin/sh',
                  '-v',str(work)+':/qa',BASE,'-c','LD_LIBRARY_PATH=/srv/openmp/qawno /srv/openmp/qawno/pawncc /qa/fixture.pwn -i/srv/openmp/qawno/include -o/qa/gravity.amx']
        built=subprocess.run(compiler,capture_output=True,text=True,timeout=120);(out/'pawn-build.log').write_text(built.stdout+built.stderr)
        if built.returncode:print(built.stdout+built.stderr);built.check_returncode()
        config_file=ROOT.parent/'ZGTA-SA-core-101/local-only/interop-openmp/release/Server/config.json'
        config=json.loads(config_file.read_text());config.update(name='ZGTA isolated gravity QA',announce=False,max_players=8,password='')
        config['network'].update(port=18932,bind='0.0.0.0',public_addr='127.0.0.1',minimum_connection_time=0,use_lan_mode=True)
        config['pawn'].update(main_scripts=['gravity 1'],side_scripts=[],legacy_plugins=[])
        config['artwork'].update(enable=False);config['rcon'].update(enable=False,password=uuid.uuid4().hex)
        (work/'config.json').write_text(json.dumps(config,indent=2)+'\n')
        (work/'Dockerfile').write_text('FROM '+BASE+'\nCOPY --chown=65534:65534 config.json /srv/openmp/config.json\nCOPY --chown=65534:65534 gravity.amx /srv/openmp/gamemodes/gravity.amx\n')
        with(out/'docker-build.log').open('w')as log:subprocess.run(['docker','build','--pull=false','-t',image,str(work)],check=True,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        subprocess.run(['docker','run','--rm','--pull=never','--cpus=0.5','--memory=256m','-d','--name',name,'-p','127.0.0.1:18932:18932/udp',image],check=True,stdout=subprocess.DEVNULL,timeout=30);created=True
        end=time.monotonic()+20
        while time.monotonic()<end:
            logs=subprocess.run(['docker','logs',name],capture_output=True,text=True,timeout=15)
            if 'Legacy Network started on' in logs.stdout+logs.stderr:break
            time.sleep(0.2)
        result=subprocess.run([str(work/'verify'),'127.0.0.1:18932',str(out/'native-report.json')],capture_output=True,text=True,timeout=100)
        (out/'native.log').write_text(result.stdout+result.stderr)
        logs=subprocess.run(['docker','logs',name],capture_output=True,text=True,timeout=30);text=logs.stdout+logs.stderr;(out/'server.log').write_text(text)
        report=json.loads((out/'native-report.json').read_text());rows=[]
        for line in text.splitlines():
            if 'GRAVITY_QA {' in line:rows.append(json.loads(line.split('GRAVITY_QA ',1)[1]))
        validations=[]
        if result.returncode==0:
            for phase in report['phases']:
                for index,peer in enumerate(report['peers']):
                    expected=phase['expected'][index]
                    matches=[r for r in rows if r['name']==peer['name'] and r['phase']==phase['phase'] and r['event']=='update' and abs(r['gravity']-expected)<0.000001]
                    assert matches,(peer['profile'],phase['phase'],'No real server update agreed with native context')
                    validations.append(dict(profile=peer['profile'],phase=phase['phase'],serverUpdates=len(matches)))
            for peer in report['peers']:
                matched=0
                for row in rows:
                    if row['name']!=peer['name'] or row['event']!='update' or abs(row['vz'])<0.01:continue
                    candidates=[s for s in peer['sent'] if abs(s['z']-row['z'])<0.0002]
                    if any(abs((math.floor(s['vz']*100+0.5)/100)/50-row['vz'])<0.0006 for s in candidates):matched+=1
                assert matched>=3,(peer['profile'],'Real physical position/normalized velocity did not reach server')
                validations.append(dict(profile=peer['profile'],physicalSyncMatches=matched))
        unchanged=all(p.read_bytes()==v for p,v in captured.items()) and all(sha(p.read_bytes())==v for p,v in frozen_bridges.items())
        assert unchanged,'Held source/library changed during live acceptance'
        final=dict(status='PASS' if result.returncode==0 else 'FAIL',native=report,serverChecks=validations,sourceUnchanged=unchanged,
                   sourceHashes={str(p):sha(data) for p,data in captured.items()},bridgeHashes={str(p):v for p,v in frozen_bridges.items()},
                   image=BASE,imageID=base['Id'],originalDataUsed=False,onlyLoopback18932=True,cpuLimit=0.5,memoryBytes=268435456)
        (out/'report.json').write_text(json.dumps(final,indent=2)+'\n');print(result.stdout+result.stderr,flush=True);result.check_returncode()
        (out.parent/'latest.json').write_text(json.dumps(dict(final,work=str(out)),indent=2)+'\n')
    finally:
        if created:subprocess.run(['docker','stop','--time','2',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
        subprocess.run(['docker','image','rm',image],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)

if __name__=='__main__':main()
