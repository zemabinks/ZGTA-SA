#!/usr/bin/env python3
"""Actual native damage feedback and browser-shaped knockdown transport."""
from pathlib import Path
import hashlib,json,os,struct,subprocess,tempfile
from smoke_native_coupling_backend import NAMES,MODULES
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/hit-backend'
def main(scenario='hit'):
    OUT=ROOT/('local-only/native-physics/tests/'+scenario+'-backend')
    stem='smoke_native_'+scenario+'_backend'
    OUT.mkdir(parents=True,exist_ok=True)
    paths=[f'ios/App/{name}.swift' for name in NAMES]+['ios/App/NativeActorAnimation.swift']+MODULES+['smoke_native_hit_backend.py',stem+'.js',stem+'.swift']
    before={p:(ROOT/p).read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp);game=work/'game';data=game/'local-only/selfhost';data.mkdir(parents=True)
        for name in MODULES:(game/name).write_bytes(before[name])
        (data/'client-catalog.json').write_text(json.dumps({'vehicles':[],'homes':[]}));(data/'weapon-catalog.json').write_text(json.dumps({'items':[],'shops':[]}))
        if scenario=='parry':
            profiles=game/'local-only/native';profiles.mkdir()
            (profiles/'melee.json').write_text(json.dumps({'weapons':[{'id':0,'blocks':True},{'id':9,'blocks':False}]}))
        world=game/'local-only/site/game/world';world.mkdir(parents=True)
        (world/'index.json').write_text(json.dumps({'detail':{'size':375,'grid':16,'origin':-3000,'cells':[{'cell':28}]},'inside':{'cells':[]}}))
        points=[1500,-2625,0,1875,-2625,0,1875,-2250,0,1500,-2250,0];indices=[0,1,2,0,2,3]
        (world/'c28.col.bin').write_bytes(struct.pack('<4I',0x324c4353,4,2,0)+struct.pack('<12f',*points)+struct.pack('<6I',*indices))
        actor=before['ios/App/NativeActorAnimation.swift'].decode();actor=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        (work/'main.swift').write_text('\n'.join(before[f'ios/App/{name}.swift'].decode() for name in NAMES)+'\n'+actor+'\n'+before[stem+'.swift'].decode())
        result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),str(work/'main.swift'),'-o',str(work/'client')],capture_output=True,text=True)
        (OUT/'compile.log').write_text(result.stdout+result.stderr);result.check_returncode()
        (work/'fixture.js').write_bytes(before[stem+'.js'])
        environment=dict(os.environ,ZGTA_JOIN_CODE='',ZGTA_JOIN_CODE_FILE='',ZGTA_DISCORD_CLIENT_ID='',ZGTA_DISCORD_CLIENT_SECRET='')
        result=subprocess.run(['node',str(work/'fixture.js'),str(game),str(work/'client'),str(OUT/'server-report.json'),str(ROOT)],capture_output=True,text=True,env=environment,timeout=40)
        unchanged=all((ROOT/p).read_bytes()==v for p,v in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(v).hexdigest() for p,v in before.items()},'output':result.stdout+result.stderr,
                'limits':['Synthetic floor/actors; actual current native transport/server with controlled duplicate and ordering fixtures','No real rendered browser, phone input, retail executable or WAN evidence']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
