#!/usr/bin/env python3
"""Actual native URLSession clients against restartable disposable backend."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,os,struct,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/connection-runtime'
OUT.mkdir(parents=True,exist_ok=True)
APP=['ServerAddress','NativeInventoryPrediction','NativeShotTargeting','NativeStreamShotClaims',
     'NativeConnectionRecovery','NativeOriginalWorldProtocol','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPLocalVitals','NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots','NativeLocalShotPackets','NativeMultiplayerClient','NativeGameplayClient']
SERVER=['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js', 'player_placement.js']
FILES=[f'ios/App/{name}.swift' for name in APP]+['ios/App/NativeActorAnimation.swift',*SERVER,
       'tests/movement/smoke_native_recovery.swift','tests/server/smoke_native_recovery_server.js','tests/movement/smoke_native_recovery.py']
inputs={p:(ROOT/p).read_bytes() for p in FILES}

def main():
    with tempfile.TemporaryDirectory(prefix='zgta-native-recovery-') as directory:
        folder=Path(directory);game=folder/'game';game.mkdir()
        for name in SERVER:(game/name).write_bytes(inputs[name])
        data=game/'local-only/selfhost';data.mkdir(parents=True)
        (data/'client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
        # Explicit synthetic stats/geometry, not archived/publisher assets.
        (data/'weapon-catalog.json').write_text(json.dumps({'items':[{'id':22,'name':'Synthetic recovery fixture',
            'ammo':100,'capacity':17,'price':0,'slot':2,'fire':'INSTANT_HIT','stats':{'loop':[0,9,0],'range':40}}],'shops':[]}))
        world=game/'local-only/site/game/world';world.mkdir(parents=True)
        (world/'index.json').write_text(json.dumps({'detail':{'size':375,'grid':16,'origin':-3000,'cells':[{'cell':59}]},'inside':{'cells':[]}}))
        vertices=[(1125,-1875,0),(1500,-1875,0),(1500,-1500,0),(1125,-1500,0)];indices=[0,1,2,0,2,3]
        mesh=struct.pack('<4I',0x324c4353,len(vertices),len(indices)//3,0)
        mesh+=b''.join(struct.pack('<3f',*point) for point in vertices)+struct.pack('<6I',*indices)
        (world/'c59.col.bin').write_bytes(mesh)
        sources=[]
        for name in APP:
            p=folder/(name+'.swift');p.write_bytes(inputs[f'ios/App/{name}.swift']);sources.append(str(p))
        actor=inputs['ios/App/NativeActorAnimation.swift'].decode()
        fragment=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        p=folder/'PedestrianMotion.swift';p.write_text('import Foundation\nimport simd\n'+fragment);sources.append(str(p))
        p=folder/'main.swift';p.write_bytes(inputs['tests/movement/smoke_native_recovery.swift']);sources.append(str(p))
        peer=folder/'peer.js';peer.write_bytes(inputs['tests/server/smoke_native_recovery_server.js'])
        executable=folder/'verify'
        compiled=subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'module-cache'),*sources,'-o',str(executable)],capture_output=True,text=True)
        (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:
            print(compiled.stdout+compiled.stderr);compiled.check_returncode()
        environment=dict(os.environ,ZGTA_JOIN_CODE='',ZGTA_JOIN_CODE_FILE='',ZGTA_DISCORD_CLIENT_ID='',ZGTA_DISCORD_CLIENT_SECRET='')
        result=subprocess.run(['node',str(peer),str(game),str(executable)],capture_output=True,text=True,env=environment,timeout=100)
        print(result.stdout,end='');print(result.stderr,end='')
        (OUT/'runtime.log').write_text(result.stdout+result.stderr)
        report={'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout,
                'coverage':['hello/inventory/world readiness barrier','wire gating + fresh peer nonce after abrupt close',
                            'checkpointed guest state through actual backend SIGKILL/restart','bounded offline retries + inactive/stopped suppression',
                            'no shot/ammunition/damage/chat replay; reset chat sequence','old HTTP refresh/action generation barriers',
                            'same-connection GET vs mutation; reentrant action busy ownership'],
                'sourceHashes':{p:hashlib.sha256(data).hexdigest() for p,data in inputs.items()},
                'liveFilesStillMatchSnapshot':{p:(ROOT/p).read_bytes()==data for p,data in inputs.items()},
                'limits':['Temporary backend state is checkpointed before SIGKILL; not an arbitrary-crash durability test',
                          'Clock is injected and stepped; real transport/HTTP/WS/backend are used',
                          'No production/QA service, device/UI, microphone or owner asset is used']}
        for line in result.stdout.splitlines():
            if line.startswith('RECOVERY_METRICS '):report['metrics']=json.loads(line[len('RECOVERY_METRICS '):])
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        result.check_returncode()

if __name__=='__main__':main()
