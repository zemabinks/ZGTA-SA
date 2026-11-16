#!/usr/bin/env python3
"""Native combat transitions against real disposable revision/ACK snapshots."""
from pathlib import Path
import hashlib,json,subprocess,tempfile

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/combat-transitions'
OUT.mkdir(parents=True,exist_ok=True)
SERVER=['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js']
APP=['ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState','NativeWeaponShotDelivery']
FILES=SERVER+[f'ios/App/{p}.swift' for p in APP]+['smoke_native_combat_transitions.swift','smoke_native_combat_transitions.py']
inputs={p:(ROOT/p).read_bytes() for p in FILES}
JS=r'''
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
let now=1700000000000;Date.now=()=>now;
const game=require(path.join(process.argv[2],'selfhost_backend.js'));
function peer(){
 const account=game.ensurePlayer({headers:{}},{setHeader(){}}),messages=[];
 const p={id:account.id,player:account.player,ready:false,lastSeen:now,closed:false,
   state:{walking:true,x:1480,y:-1738,z:13},send:m=>messages.push(structuredClone(m))};
 game.peers.add(p);game.onMessage(p,{t:'hi',nativeInventory:true,inventoryAck:1});
 p.player.inventory={revision:0,selected:22,weapons:{22:{clip:4,rest:30},28:{clip:5,rest:20}}};p.player.cash=1000;
 return p;
}
function snapshot(p){return structuredClone(game.inventoryState(p.player,p));}
try{
 const p=peer(),baseline=snapshot(p);game.action(p.player,'weapon.reload',{});const started=snapshot(p);
 now+=600;game.action(p.player,'weapon.buy',{weapon:48});const armour=snapshot(p);
 assert.equal(armour.reload.until,started.reload.until);assert(armour.revision>started.revision);
 now+=100;p.lastSeen=now;game.onMessage(p,{t:'shot',w:22,c:p.inventoryConnection,s:1,o:[1480,-1738,14.35],h:[1482,-1738,14.35]});
 const rejected=snapshot(p);assert.equal(rejected.ack.processedShot,1);assert.equal(rejected.revision,armour.revision);
 now=1700000001900;const completed=snapshot(p);assert.equal(completed.reload,null);
 const q=peer(),secondBaseline=snapshot(q);game.action(q.player,'weapon.reload',{});const firstReload=snapshot(q);
 now+=300;game.action(q.player,'weapon.select',{weapon:22});game.action(q.player,'weapon.reload',{});const replaced=snapshot(q);
 assert(replaced.reload.until>firstReload.reload.until);
 fs.writeFileSync(process.argv[3],JSON.stringify({baseline,started,armour,rejected,completed,secondBaseline,firstReload,replaced}));
}finally{clearInterval(game.tick);clearInterval(game.projectileTimer);clearTimeout(game.saveTimer);}
'''

def main():
    with tempfile.TemporaryDirectory(prefix='combat-',dir=OUT) as temporary:
        folder=Path(temporary);server=folder/'server';server.mkdir()
        for name in SERVER:(server/name).write_bytes(inputs[name])
        data=server/'local-only/selfhost';data.mkdir(parents=True)
        (data/'client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
        items=[{'id':n,'name':'Synthetic combat fixture','ammo':50,'capacity':17 if n==22 else 50,'price':0,'slot':slot,'fire':'INSTANT_HIT','stats':{'loop':[0,9,0]}} for n,slot in [(22,2),(28,4)]]
        items.append({'id':48,'name':'Synthetic vest','ammo':1,'capacity':1,'price':0,'slot':-1,'fire':'NONE'})
        (data/'weapon-catalog.json').write_text(json.dumps({'items':items,'armourID':48,'shops':[{'id':'fixture','name':'Fixture','door':[1480,-1738,13]}]}))
        probe=folder/'reference.js';probe.write_text(JS);reference=folder/'reference.json'
        subprocess.run(['node',str(probe),str(server),str(reference)],check=True)
        sources=[]
        for name in APP:
            p=folder/(name+'.swift');p.write_bytes(inputs[f'ios/App/{name}.swift']);sources.append(str(p))
        p=folder/'main.swift';p.write_bytes(inputs['smoke_native_combat_transitions.swift']);sources.append(str(p))
        exe=folder/'verify';subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(OUT/'module-cache'),*sources,'-o',str(exe)],check=True)
        result=subprocess.run([str(exe),str(reference)],capture_output=True,text=True)
        print(result.stdout,end='');print(result.stderr,end='')
        (OUT/'reference.json').write_bytes(reference.read_bytes())
        (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
            'sourceHashes':{p:hashlib.sha256(data).hexdigest() for p,data in inputs.items()},
            'liveFilesStillMatchSnapshot':{p:(ROOT/p).read_bytes()==data for p,data in inputs.items()},
            'evidence':'Actual independent server inventory action/state and per-peer ACK code; synthetic catalog, no assets/services',
            'limit':'Local reload policy/transport transitions, not retail reload-duration verification'},indent=2)+'\n')
        result.check_returncode()
if __name__=='__main__':main()
