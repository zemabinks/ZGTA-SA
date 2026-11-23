#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual native transport and isolated backend passive-status round trip."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,time
ROOT=Path(__file__).resolve().parents[2]

def main():
    os.setpriority(os.PRIO_PROCESS,0,15)
    names=['ServerAddress','NativeConnectionRecovery','NativeInventoryPrediction',
           'NativeShotTargeting','NativeStreamShotClaims','NativeOriginalWorldProtocol',
           'NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeSAMPProtocol',
           'NativeSAMPGameplayCommands','NativeSAMPLocalVitals','NativeAmbientPedestrianProtocol',
           'NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots',
           'NativeLocalShotPackets','NativeMultiplayerClient']
    native=[ROOT/'ios/App'/(n+'.swift')for n in names]
    backend=[ROOT/n for n in ['selfhost_backend.js','optional_discord.js','weapon_inventory.js',
                             'world_collision.js','local_projectiles.js','player_placement.js']]
    actor=ROOT/'ios/App/NativeActorAnimation.swift'
    wire=Path(__file__).with_name('smoke_native_passive_wire.swift')
    server=Path(__file__).with_name('smoke_native_passive_server.js')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    frozen={str(p):sha(p)for p in native+backend+[actor,wire,server,Path(__file__).resolve()]}
    out=ROOT/'local-only/research/passive-transport'/str(time.time_ns());out.mkdir(parents=True)
    report=dict(status='RUNNING',startedAt=time.time(),sourceHashes=frozen,
                scope='Complete native HTTP/WebSocket transport, actual backend/Peer and browser-style second protocol peer. Authored accounts/position; private action endpoint invokes production passive action. No original resources, renderer, browser UI, external service or retail acceptance.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']))+'\n')
    save()
    try:
        text=actor.read_text();motion=text[text.index('struct NativePedestrianMotion {'):text.index('struct NativeWeaponAnimation {')]
        source=out/'main.swift';source.write_text('\n'.join(p.read_text()for p in native)+'\n'+motion+'\n'+wire.read_text())
        with(out/'compile.log').open('x')as log:
            r=subprocess.run(['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone',
                              '-module-cache-path',str(out/'modules'),str(source),'-o',str(out/'client')],stdout=log,stderr=subprocess.STDOUT,timeout=300)
        report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-3000:]
        game=out/'game';data=game/'local-only/selfhost';data.mkdir(parents=True)
        for p in backend:shutil.copy2(p,game/p.name)
        (data/'client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
        (data/'weapon-catalog.json').write_text('{"items":[],"shops":[]}')
        environment=dict(os.environ,ZGTA_JOIN_CODE='',ZGTA_JOIN_CODE_FILE='',ZGTA_DISCORD_CLIENT_ID='',ZGTA_DISCORD_CLIENT_SECRET='')
        with(out/'runtime.log').open('x')as log:
            r=subprocess.run(['node',str(server),str(game),str(out/'client')],cwd=game,env=environment,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        report.update(runtimeExit=r.returncode,output=(out/'runtime.log').read_text());save()
        assert r.returncode==0,report['output'];report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(seconds=time.time()-report['startedAt'],sourcesHeld=all(sha(Path(n))==h for n,h in frozen.items()));save()
        print({k:v for k,v in report.items()if k!='sourceHashes'},flush=True)
if __name__=='__main__':main()
