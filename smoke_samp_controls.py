#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual native NMP adapter controls and driver transitions on owned open.mp.

Requires the existing owner-local official open.mp QA image; never downloads
unofficial server distributions. Uses separate matching loopbackUDP7791.
"""
from pathlib import Path
import argparse,hashlib,json,platform,subprocess,tempfile,time,uuid
ROOT=Path(__file__).resolve().parent
BASE='zgta-openmp-qa:1.6.7.3218-files'
NAMES=['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeShotTargeting',
       'NativeStreamShotClaims','NativeSAMPGameplayCommands','NativeOriginalWorldProtocol','NativeOriginalWorldCommands',
       'NativeOriginalWorldVitals','NativeSAMPLocalVitals','NativeMultiplayerClient','NativeSAMPSkinCatalog',
       'NativeSAMPProtocol','NativeSAMPVehicleCoordinates','NativeSAMPClient','NativeSAMPWorldConnection','NativeSAMPInput']

def run(args,**kwargs):return subprocess.run(args,check=True,**kwargs)
def validate_server(lines,cases):
    rows=[]
    for line in lines.splitlines():
        if 'ZGTA_QA {' in line:rows.append(json.loads(line.split('ZGTA_QA ',1)[1]))
    results=[]
    for case in cases:
        own=[row for row in rows if row['name']==case['nickname']]
        for phase,expected,state in [('foot_pressed',case['expectedFoot'],1),('car_pressed',case['expectedCar'],2)]:
            # Additional keys occupy the weapon byte's high2bits in sync; the
            # actual server combines them into the documented GetPlayerKeys.
            additional={0:0,1:65536,2:131072,3:262144}[expected['special']]
            wanted=dict(keys=expected['keys']|additional,lr=expected['lr'],ud=expected['ud'],weapon=expected['weapon'],state=state)
            assert any(row['phase']==phase and row['event']=='update' and all(row[k]==v for k,v in wanted.items())for row in own),(case['profile'],phase,wanted,own)
            expected_z=13.5 if phase=='foot_pressed'else case['networkCarPressed'][2]
            assert any(row['phase']==phase and row['event']=='update' and abs(row['z']-expected_z)<0.0001 for row in own),'Nativefeet/modelroot conversion disagrees with actualserverposition'
        for phase,state in [('foot_released',1),('car_released',2),('exit_foot',1)]:
            assert any(row['phase']==phase and row['event']=='update' and row['state']==state and row['keys']==row['lr']==row['ud']==0 for row in own),(case['profile'],phase,own)
        assert any(row['phase']=='frozen'and row['event']=='update'and row['keys']==row['lr']==row['ud']==0 for row in own),'Server freeze leaked held controls'
        assert any(row['phase']=='spectating'and row['state']==9 and abs(row['z']-20)<0.0001 and row['keys']==8 and row['lr']==-128 and row['ud']==128 for row in own),'Actual spectator212 camera/axes did not reach server unchanged'
        assert sum(row['event']=='spawn'for row in own)==3,'Each of two spectator exits must complete exactlyone server spawn'
        enter=next(i for i,row in enumerate(own)if row['event']=='enter_rpc')
        driver=next(i for i,row in enumerate(own)if i>enter and row['state']==2)
        leave=next(i for i,row in enumerate(own)if i>driver and row['event']=='exit_rpc')
        foot=next(i for i,row in enumerate(own)if i>leave and row['state']==1)
        assert sum(row['event']=='enter_rpc'for row in own)==2,'Each of two driver episodes must notify enter exactlyonce'
        assert sum(row['event']=='exit_rpc'for row in own)==2,'Each of two driver episodes must notify exit exactlyonce'
        for phase,point,hp in [('cache_driver',case['cachePoses']['driver'],875),('cache_exit',case['cachePoses']['final'],840),('cache_respawn',case['cachePoses']['final'],840)]:
            assert any(row['phase']==phase and all(abs(row[k]-v)<.001 for k,v in zip(['carX','carY','carZ'],point))and row['carHP']==hp for row in own),(phase,point,hp,own)
        results.append({'profile':case['profile'],'status':'PASS','serverRows':own,
                        'transitionRowIndices':dict(enterRPC=enter,firstDriver=driver,exitRPC=leave,onFoot=foot)})
    return results

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vehicle-metadata',type=Path,help='Explicit owner-generated vehicles.physics.json; exercises nativebody/modelroot conversion through realUDP')
    options=parser.parse_args()
    metadata=options.vehicle_metadata.read_bytes()if options.vehicle_metadata else None
    out=ROOT/('local-only/research/samp-controls-catalog'if metadata is not None else'local-only/research/samp-controls');out.mkdir(parents=True,exist_ok=True)
    paths=[f'ios/App/{n}.swift'for n in NAMES]+['ios/App/NativeActorAnimation.swift',
           'smoke_samp_controls.py','smoke_samp_controls.swift','smoke_samp_controls.pwn']
    before={p:(ROOT/p).read_bytes()for p in paths}
    image='zgtasa-controls-qa:'+uuid.uuid4().hex[:10];name='zgtasa-controls-qa-'+uuid.uuid4().hex[:10]
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
        (work/'main.swift').write_bytes(before['smoke_samp_controls.swift'])
        if metadata is not None:(work/'vehicle-metadata.json').write_bytes(metadata)
        command=['xcrun','swiftc','-Onone','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-samp/include'),
                 *sources,str(work/'main.swift'),'-L',str(ROOT/('local-only/native-samp/macos-'+platform.machine())),
                 '-lzgtasa_samp','-lresolv','-framework','CoreFoundation','-framework','Security','-o',str(work/'verify')]
        compiled=subprocess.run(command,capture_output=True,text=True);(out/'compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
        (work/'fixture.pwn').write_bytes(before['smoke_samp_controls.pwn'])
        command=['docker','run','--rm','--pull=never','--network=none','--entrypoint','/bin/sh','-v',str(work)+':/qa',BASE,'-c',
                 'LD_LIBRARY_PATH=/srv/openmp/qawno /srv/openmp/qawno/pawncc /qa/fixture.pwn -i/srv/openmp/qawno/include -o/qa/controls.amx']
        compiled=subprocess.run(command,capture_output=True,text=True);(out/'pawn-compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
        config=json.loads(config_path.read_text());config.update(name='ZGTA isolated controls QA',announce=False,max_players=8)
        config['network'].update(port=7791,bind='0.0.0.0',public_addr='127.0.0.1',minimum_connection_time=0,use_lan_mode=True,
                                 on_foot_sync_rate=45,in_vehicle_sync_rate=55,aiming_sync_rate=65,stream_rate=100)
        config['pawn'].update(main_scripts=['controls 1'],side_scripts=[],legacy_plugins=[])
        config['artwork'].update(enable=False)
        config['rcon'].update(enable=False,password=uuid.uuid4().hex)
        (work/'config.json').write_text(json.dumps(config,indent=2)+'\n')
        (work/'Dockerfile').write_text('FROM '+BASE+'\nCOPY --chown=65534:65534 config.json /srv/openmp/config.json\nCOPY --chown=65534:65534 controls.amx /srv/openmp/gamemodes/controls.amx\n')
        with(out/'docker-build.log').open('w')as log:run(['docker','build','--pull=false','-t',image,str(work)],stdout=log,stderr=subprocess.STDOUT)
        started=False
        try:
            run(['docker','run','--rm','--pull=never','-d','--name',name,'-p','127.0.0.1:7791:7791/udp',image],stdout=subprocess.DEVNULL);started=True
            deadline=time.monotonic()+12
            while time.monotonic()<deadline:
                logs=subprocess.run(['docker','logs',name],capture_output=True,text=True)
                if 'Legacy Network started on'in logs.stdout+logs.stderr:break
                time.sleep(0.2)
            arguments=[str(work/'verify'),'127.0.0.1:7791',str(out/'native-report.json')]
            if metadata is not None:arguments.append(str(work/'vehicle-metadata.json'))
            result=subprocess.run(arguments,capture_output=True,text=True,timeout=80)
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
                    'serverImage':BASE,'serverImageID':base_metadata['Id'],'compiledIndependentFixtureSHA256':hashlib.sha256((work/'controls.amx').read_bytes()).hexdigest(),
                    'vehicleMetadata':None if metadata is None else {'sha256':hashlib.sha256(metadata).hexdigest(),'sourceUnchanged':options.vehicle_metadata.read_bytes()==metadata,'mode':'actual owner-generated catalog; numeric origin data stays local'},
                    'ports':'Separate matching loopback7791UDP;7777,8801,phone and production services untouched',
                    'limits':['Actual native semantic input→NMP→legacyadapter→GoUDP→official open.mpGetPlayerKeys/state/weapon callbacks and separate stationary native observer',
                              'Independent disposable Pawn mode creates a real stock411; deterministic native poses isolate protocol/ownership and do not validate driving physics or rendered touch/controller hardware',
                              '037 andDL stock protocol profiles on officialopen.mp; no universal proprietarySA-MP/plugin, custommodel, retail1:1 or thirdpartyservice claim']}
            (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='')
            if validation_error:print(validation_error)
            result.check_returncode();assert unchanged;assert validation_error is None,validation_error
        finally:
            if started:subprocess.run(['docker','stop','--time','1',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            subprocess.run(['docker','image','rm',image],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
if __name__=='__main__':main()
