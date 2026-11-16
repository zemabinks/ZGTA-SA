#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Fractional local vital owner and actual RPC115/death on owned open.mp.

Uses a disposable official existing server image on matching loopback7795.
No assets, third-party servers, guessed incoming bullet hits or health ACK.
"""
from pathlib import Path
import hashlib,json,platform,subprocess,tempfile,time,uuid
from smoke_samp_controls import NAMES
ROOT=Path(__file__).resolve().parent
BASE='zgta-openmp-qa:1.6.7.3218-files'
def run(args,**kwargs):return subprocess.run(args,check=True,**kwargs)
def validate_server(lines,cases):
    rows=[json.loads(line.split('ZGTA_VITALS ',1)[1])for line in lines.splitlines()if 'ZGTA_VITALS {'in line]
    results=[]
    for case in cases:
        own=[r for r in rows if r['name']==case['nickname']]
        for phase,damage,weapon,count in [('high',.125,53,1),('fraction',.125,53,10),('armour',26.25,0,1),('fall',2,54,1),('fatal_drown',.25,53,1),('fatal_driver',.25,54,1)]:
            actual=[r for r in own if r['phase']==phase and r['event']=='taking'and abs(r['amount']-damage)<1e-6 and r['weapon']==weapon and r['source']==65535 and r['body']==3]
            assert len(actual)==count,(case['profile'],phase,damage,count,actual,own)
        for phase,hp,ap in [('high',255,255),('fraction',34,12),('armour',80,0),('fall',32,12)]:
            assert any(r['phase']==phase and r['event']=='update'and r['health']==hp and r['armour']==ap for r in own),(phase,hp,ap,own)
        death=[r for r in own if r['event']=='death']
        assert [(r['phase'],r['weapon'],r['source'])for r in death]==[('fatal_drown',53,65535),('fatal_driver',54,65535),('fatal_wreck',51,65535),('fatal_unknown',255,65535)],death
        assert not any(r['event']=='taking'and r['phase']in ['fatal_wreck','fatal_unknown']for r in own),'FatalAPI invented damageamount115'
        assert not any(r['event']=='taking'and r['phase']=='fall'and r['amount']==1.75 for r in own),'Absolutehealthsetter inventedfall damage115'
        assert sum(r['event']=='spawn'for r in own)==4,own
        assert any(r['phase']=='fatal_driver'and r['state']==2 for r in own),own
        results.append({'profile':case['profile'],'status':'PASS','serverRows':own})
    return results
def main():
    out=ROOT/'local-only/research/samp-vitals';out.mkdir(parents=True,exist_ok=True)
    paths=[f'ios/App/{n}.swift'for n in NAMES]+['ios/App/NativeActorAnimation.swift',
           'smoke_samp_vitals.py','smoke_samp_vitals.swift','smoke_samp_vitals.pwn']
    before={p:(ROOT/p).read_bytes()for p in paths}
    image='zgtasa-vitals-qa:'+uuid.uuid4().hex[:10];name='zgtasa-vitals-qa-'+uuid.uuid4().hex[:10]
    config_path=ROOT/'local-only/interop-openmp/release/Server/config.json'
    if not config_path.exists():config_path=ROOT.parent/'ZGTA-SA-core-101/local-only/interop-openmp/release/Server/config.json'
    base_metadata=json.loads(subprocess.check_output(['docker','image','inspect',BASE,'--format','{{json .}}'],text=True))
    with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as temp:
        work=Path(temp);work.chmod(0o777)
        sources=[]
        for n in NAMES:
            p=work/(n+'.swift');p.write_bytes(before[f'ios/App/{n}.swift']);sources.append(str(p))
        actor=before['ios/App/NativeActorAnimation.swift'].decode()
        motion=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        (work/'PedestrianMotion.swift').write_text('import Foundation\nimport simd\n'+motion);sources.append(str(work/'PedestrianMotion.swift'))
        (work/'main.swift').write_bytes(before['smoke_samp_vitals.swift'])
        command=['xcrun','swiftc','-Onone','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-samp/include'),
                 *sources,str(work/'main.swift'),'-L',str(ROOT/('local-only/native-samp/macos-'+platform.machine())),
                 '-lzgtasa_samp','-lresolv','-framework','CoreFoundation','-framework','Security','-o',str(work/'verify')]
        compiled=subprocess.run(command,capture_output=True,text=True);(out/'compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
        (work/'fixture.pwn').write_bytes(before['smoke_samp_vitals.pwn'])
        command=['docker','run','--rm','--pull=never','--network=none','--entrypoint','/bin/sh','-v',str(work)+':/qa',BASE,'-c',
                 'LD_LIBRARY_PATH=/srv/openmp/qawno /srv/openmp/qawno/pawncc /qa/fixture.pwn -i/srv/openmp/qawno/include -o/qa/vitals.amx']
        compiled=subprocess.run(command,capture_output=True,text=True);(out/'pawn-compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
        config=json.loads(config_path.read_text());config.update(name='ZGTA isolated vital QA',announce=False,max_players=8)
        config['network'].update(port=7795,bind='0.0.0.0',public_addr='127.0.0.1',minimum_connection_time=0,use_lan_mode=True,
                                 on_foot_sync_rate=45,in_vehicle_sync_rate=55,aiming_sync_rate=65,stream_rate=100)
        config['pawn'].update(main_scripts=['vitals 1'],side_scripts=[],legacy_plugins=[])
        config['artwork'].update(enable=False)
        config['rcon'].update(enable=False,password=uuid.uuid4().hex)
        (work/'config.json').write_text(json.dumps(config,indent=2)+'\n')
        (work/'Dockerfile').write_text('FROM '+BASE+'\nCOPY --chown=65534:65534 config.json /srv/openmp/config.json\nCOPY --chown=65534:65534 vitals.amx /srv/openmp/gamemodes/vitals.amx\n')
        with(out/'docker-build.log').open('w')as log:run(['docker','build','--pull=false','-t',image,str(work)],stdout=log,stderr=subprocess.STDOUT)
        started=False
        try:
            run(['docker','run','--rm','--pull=never','-d','--name',name,'-p','127.0.0.1:7795:7795/udp',image],stdout=subprocess.DEVNULL);started=True
            deadline=time.monotonic()+12
            while time.monotonic()<deadline:
                logs=subprocess.run(['docker','logs',name],capture_output=True,text=True)
                if 'Legacy Network started on'in logs.stdout+logs.stderr:break
                time.sleep(0.2)
            native_path=out/'native-report.json'
            if native_path.exists():native_path.unlink()
            result=subprocess.run([str(work/'verify'),'127.0.0.1:7795',str(native_path)],capture_output=True,text=True,timeout=90)
            (out/'native.log').write_text(result.stdout+result.stderr)
            logs=subprocess.run(['docker','logs',name],capture_output=True,text=True);server_log=logs.stdout+logs.stderr;(out/'server.log').write_text(server_log)
            native=json.loads((out/'native-report.json').read_text())
            unchanged=all((ROOT/p).read_bytes()==b for p,b in before.items())
            server_checks=[];validation_error=None
            if result.returncode==0:
                try:server_checks=validate_server(server_log,native['cases'])
                except Exception as e:validation_error=repr(e)
            report={'status':'PASS'if result.returncode==0 and unchanged and validation_error is None else'FAIL',
                    'sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(b).hexdigest()for p,b in before.items()},
                    'native':native,'serverChecks':server_checks,'serverValidationError':validation_error,'output':result.stdout+result.stderr,
                    'serverImage':BASE,'serverImageID':base_metadata['Id'],'compiledIndependentFixtureSHA256':hashlib.sha256((work/'vitals.amx').read_bytes()).hexdigest(),
                    'ports':'Separate matching loopback7795UDP;7777,8801,phone and production services untouched',
                    'limits':['Actual fractional local vital owner→NMP→legacyadapter→GoUDP→official open.mp OnPlayerTakeDamage115 and OnPlayerDeath53 callbacks',
                              'Independent disposable Pawn mode creates a real stock411; deterministic poses isolate local health ownership and foot/car fatal reporting, not rendered damage/retail1:1',
                              '037 andDL stock protocol profiles on officialopen.mp; no universal proprietarySA-MP/plugin, custommodel, retail1:1 or thirdpartyservice claim']}
            (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='')
            if validation_error:print(validation_error)
            result.check_returncode();assert unchanged;assert validation_error is None,validation_error
        finally:
            if started:subprocess.run(['docker','stop','--time','1',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            subprocess.run(['docker','image','rm',image],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
if __name__=='__main__':main()
