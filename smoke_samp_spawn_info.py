#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual client/adapter spawn-data ownership; authored packets and UI boundary."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import time
from smoke_native_actor_selection import extract

ROOT=Path(__file__).resolve().parent
NAMES=['NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPClient','NativeSAMPWorldConnection',
       'NativeConnectionRecovery','NativeSAMPSkinCatalog','NativeSAMPVehicleCoordinates','NativeActorSelection']


def sha(data):return hashlib.sha256(data).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-client',type=Path,help='Optional historical actual Client source; original RPC68 dispatch must fail the same live-ownership assertion.')
    parser.add_argument('--historical-gvc',type=Path,help='Optional historical showLegacyClass source; reproduce its deferred-dismissal metadata race with current helpers.')
    parser.add_argument('--compile-timeout',type=int,default=900,help='Bound the single-thread whole-module host compile (seconds, maximum900).')
    parser.add_argument('--out',type=Path,default=ROOT/'local-only/research/legacy-spawn-info-116')
    args=parser.parse_args();out=args.out.resolve()
    if not 1<=args.compile_timeout<=900:raise SystemExit('Compile timeout must be1...900 seconds.')
    if (ROOT/'local-only').resolve() not in out.parents:raise SystemExit('Keep outputs private under this checkout local-only.')
    out.mkdir(parents=True,exist_ok=True)
    paths=[f'ios/App/{name}.swift'for name in NAMES]+['ios/App/NativeMultiplayerClient.swift','ios/App/NativeGameViewController.swift',
            'smoke_samp_spawn_info.py','smoke_samp_spawn_info.swift','smoke_native_actor_selection.py']
    inputs={p:(ROOT/p).read_bytes()for p in paths}
    network=inputs['ios/App/NativeMultiplayerClient.swift'].decode();vc=inputs['ios/App/NativeGameViewController.swift'].decode()
    wire='\n\n'.join(extract(network,'struct '+name+' {')for name in ['NativeVehicleSeatSession','RemotePlayer','RemoteVehicle'])
    protocol=extract(network,'protocol NativeLegacyWorldConnection:')
    function=extract(vc,'private func receiveLegacyEvent(')
    def case(name):
        marker='        case "'+name+'":';at=function.index(marker)
        end=re.search(r'^        (?:case |default:)',function[at+len(marker):],re.M)
        assert end,name
        return function[at:at+len(marker)+end.start()]
    cases='\n'.join(case(name)for name in ['class','spawnInfo','spawn','weapon'])
    methods='\n\n'.join(extract(vc,marker)for marker in ['private func showLegacyClass(',
        'private func refreshLegacySpawnInfo(', 'private var legacyClassArtworkReady:', 'private func legacyClassCanSpawn(',
        'private func legacyClassMessage(', 'private func updateLegacyClassAdmission(', 'private func actorSelectionChanged(',
        'private func requestLegacyClassSpawn('])
    # The placement boundary is explicit and matches the NMP's only position
    # branch. Class and spawnInfo events are not silently treated as teleports.
    assert 'case "position":if let p=message["point"]as?SIMD3<Float>{self.onTeleport?(p,message["heading"]as?Float)}' in network
    assert 'case "class":' not in extract(network,'private func installLegacy(')
    harness=inputs['smoke_samp_spawn_info.swift'].decode()
    for marker,text in [('ACTUAL_WIRE_TYPES',wire),('ACTUAL_LEGACY_PROTOCOL',protocol),
                        ('ACTUAL_CLASS_EVENT_CASES',cases),('ACTUAL_CLASS_METHODS',methods)]:
        assert harness.count('// '+marker)==1;harness=harness.replace('// '+marker,text)
    historical_hash=None;historical_owner='';historical_check=''
    if args.historical_gvc:
        old_gvc=args.historical_gvc.resolve().read_bytes();historical_hash=sha(old_gvc)
        old_show=extract(old_gvc.decode(),'private func showLegacyClass(').replace('func showLegacyClass(','override func showLegacyClass(',1)
        historical_owner='class HistoricalClassOwner:ClassOwner {\n'+old_show+'\n}'
        historical_check='''let historical=HistoricalClassOwner(adapter)
        historical.renderer!.setLegacySkin(7)
        let pending=Controller();pending.deferDismiss=true;historical.present(pending,animated:false)
        historical.showLegacyClass(skin:7)
        historical.refreshLegacySpawnInfo(skin:287,selection:true)
        pending.finishDismiss()
        try check(historical.legacyClassSkin==287 && historical.presentedViewController==nil,"Historical captured-skin dismissal failure was not reproduced")'''
    harness=harness.replace('// HISTORICAL_PRESENTATION_OWNER',historical_owner).replace('// HISTORICAL_PRESENTATION_CHECK',historical_check)
    work=out/('snapshot-'+str(time.time_ns()));work.mkdir()
    for name in NAMES:
        if name=='NativeSAMPClient':continue
        (work/(name+'.swift')).write_bytes(inputs[f'ios/App/{name}.swift'])
    (work/'Fixture.swift').write_text(harness)
    results=[]
    def run(label,client):
        source=client.decode().replace('import ZGTASAMPTransport\n','')
        marker='    private func receive(_ data:Data)throws{';assert source.count(marker)==1
        source=source.replace(marker,'    func receive(_ data:Data)throws{',1)
        extra=False
        if 'var onSpawnInfo:' not in source:
            # Unused API compatibility only: historical RPC68 still calls its
            # exact original onClass branch. This member is never invoked.
            signature='    var onClass:((NativeSAMPProtocol.Spawn)->Void)?'
            assert source.count(signature)==1
            source=source.replace(signature,signature+'\n    var onSpawnInfo:((NativeSAMPProtocol.Spawn)->Void)?',1);extra=True
        client_file=work/(label+'-Client.swift');client_file.write_text(source)
        binary=work/label
        command=['xcrun','swiftc','-Onone','-whole-module-optimization','-num-threads','1','-swift-version','5','-module-cache-path',str(out/'modules'),
                 *[str(work/(n+'.swift'))for n in NAMES if n!='NativeSAMPClient'],str(client_file),str(work/'Fixture.swift'),'-o',str(binary)]
        (out/(label+'-command.json')).write_text(json.dumps(command,indent=2)+'\n')
        begin=time.monotonic()
        with (out/(label+'-compile.log')).open('w')as log:
            child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            try:code=child.wait(timeout=args.compile_timeout)
            except subprocess.TimeoutExpired:
                try:os.killpg(child.pid,signal.SIGTERM)
                except ProcessLookupError:pass
                try:child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    try:os.killpg(child.pid,signal.SIGKILL)
                    except ProcessLookupError:pass
                    child.wait()
                (out/(label+'-timeout.json')).write_text(json.dumps({'status':'COMPILE_TIMEOUT','seconds':args.compile_timeout,'command':command,'sourceHashes':{p:sha(v)for p,v in inputs.items()}},indent=2)+'\n')
                raise
        if code:raise RuntimeError(label+' compile failed; retained log')
        ran=subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
        (out/(label+'-runtime.log')).write_text(ran.stdout+ran.stderr)
        result={'label':label,'compileExit':0,'runExit':ran.returncode,'seconds':time.monotonic()-begin,
                'clientSHA256':sha(client),'historicalUnusedCallbackCompatibility':extra,'result':json.loads(ran.stdout)}
        results.append(result);return result
    negative_hash=None
    if args.negative_client:
        negative=args.negative_client.resolve().read_bytes();negative_hash=sha(negative)
        old=run('historical-negative',negative)
        assert old['runExit']>0 and old['result']['status']=='FAIL' and old['result']['failure']=='RPC68 reopened class selection while live',old
    current=run('current',inputs['ios/App/NativeSAMPClient.swift'])
    assert current['runExit']==0 and current['result']['status']=='PASS',current
    assert all((ROOT/p).read_bytes()==v for p,v in inputs.items()),'Scoped source changed during gate'
    if args.negative_client:assert sha(args.negative_client.resolve().read_bytes())==negative_hash
    if args.historical_gvc:assert sha(args.historical_gvc.resolve().read_bytes())==historical_hash
    report={'status':'PASS','sourceUnchanged':True,'results':results,'sourceHashes':{p:sha(v)for p,v in inputs.items()},
            'snapshot':str(work),'boundary':['Actual complete Client/WorldConnection/Protocol/command/coordinate/skin/admission sources',
                'Actual selected GVC cases and class admission methods; recording UI/resource readiness is an explicit boundary',
                'Recording ABI accepts/copies outgoing frames, never opens or polls a socket; no live join/UDP transport claim',
                'NMP position-event routing checked against source; full NMP and native renderer are not executed',
                'Unused HTTP fails immediately; no original game resources or live app state'],
            'historicalPresentationSHA256':historical_hash,'historicalDeferredPresentationReproduced':historical_hash is not None,
            'noRenderedOrRetailAcceptance':True}
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':main()
