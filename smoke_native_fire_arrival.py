#!/usr/bin/env python3
"""Real native CLP shot events against independent receive-time rate validation.

Owner assets are required locally. This is a transport/animation boundary test,
not original retail-runtime, hit geometry or physical-device acceptance.
"""
from pathlib import Path
import hashlib,json,subprocess,tempfile

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/fire-arrival'
NAMES=['NativeActorAnimation','NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeRiderAnimation']
SWIFT=r'''import Foundation
let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game")
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:game.appendingPathComponent("native/models/animations.clips.bin")))!
let definitions=try NativeFootAnimationDefinitions(data:Data(contentsOf:game.appendingPathComponent("world/peds.json")))
let weapons=try NativeFootWeaponAnimation.load(data:Data(contentsOf:game.appendingPathComponent("native/foot-animation.json")))
var rows:[[String:Any]]=[]
for id in [22,26,28,30,37,41,42] {for crouched in [false,true] {
 let animator=NativeFootAnimation(library:library,style:definitions.style(model:"bmori",library:library),random:{0.37});animator.arm(weapons[id])
 var input=NativeFootAnimation.Input();input.crouch=crouched;input.gun = .init(pitch:0,yaw:0)
 for _ in 0..<60 {animator.control(.init(aim:true,ready:true));_=animator.update(delta:1.0/60,input:input)}
 var times:[Int]=[]
 for tick in 1...1200 {
  animator.control(.init(fire:true,aim:true,held:true,ready:true))
  let frame=animator.update(delta:1.0/60,input:input)
  for _ in frame.shots {times.append(tick)}
 }
 rows.append(["id":id,"crouched":crouched,"ticks":times])
}}
let data=try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]);FileHandle.standardOutput.write(data)
'''
NODE=r'''
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),Module=require('node:module');
const root=path.resolve(process.argv[2]),out=path.resolve(process.argv[3]),filename=path.join(root,'weapon_inventory.js');
const source=fs.readFileSync(filename,'utf8'),create=require(filename).create;
const catalog=JSON.parse(fs.readFileSync(path.join(root,'local-only/selfhost/weapon-catalog.json')));
const timingDefinitions=JSON.parse(fs.readFileSync(path.join(root,'local-only/site/game/native/foot-animation.json'))).weapons;
const ids=[22,26,28,30,37,41,42];
// Synthetic large magazines isolate timing, including utility profiles that
// are absent from the shop. No utility purchase/reload/damage claim is made.
const fixture={items:ids.map(id=>({...catalog.items.find(i=>i.id===id),id,name:'Rate fixture',slot:id,capacity:9999,ammo:9999,price:0})),shops:[]};
const rows=JSON.parse(fs.readFileSync(path.join(out,'emissions.json')));
function run(factory){
 const results=[];
 for(const row of rows)for(const hz of [15,30,60,120,144])for(const jitter of [false,true]){
  const store=factory(fixture,{timingDefinitions}),p={health:100,inventory:{selected:row.id,weapons:{[row.id]:{clip:9999,rest:0}}}};
  let previous=0,accepted=0,rejections=[];
  row.ticks.forEach((tick,i)=>{
   const frame=Math.ceil(tick*hz/60-1e-9),display=frame/hz*1000;
   const delay=jitter?[20,0,10,3,16,7,19,1][frame%8]:0;
   const at=Math.max(previous,Math.round(display+delay));previous=at;
   const r=store.acceptShot(p,row.id,1700000000000+at,{sequence:i+1});
   if(r.ok)accepted++;else rejections.push({tick,at,reason:r.reason});
  });
  results.push({id:row.id,crouched:row.crouched,hz,jitter,emitted:row.ticks.length,accepted,rejections});
 }
 return results;
}
const after=run(create),seed='Math.max(0,now-inventory.lastShotAt)/interval):timing.capacity};';
assert(source.includes(seed)&&source.includes('capacity:stream?5:2'),'Historical control markers changed');
const old=new Module(filename,module);old.filename=filename;old.paths=module.paths;
old._compile(source.replace(seed,'Math.max(0,now-inventory.lastShotAt)/interval):1};').replace('capacity:stream?5:2','capacity:stream?4:2'),filename);
const before=run(old.exports.create),count=rs=>rs.reduce((n,r)=>n+r.rejections.length,0);
fs.writeFileSync(path.join(out,'after.json'),JSON.stringify(after,null,2)+'\n');
fs.writeFileSync(path.join(out,'before.json'),JSON.stringify(before,null,2)+'\n');
assert.equal(count(after),0,'Valid real-native events rejected');assert(count(before)>0,'Historical native failure was not reproduced');
console.log(JSON.stringify({cases:after.length,emissions:after.reduce((n,r)=>n+r.emitted,0),afterRejections:count(after),beforeRejections:count(before),beforeFailingCases:before.filter(r=>r.rejections.length).length}));
'''


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    paths=[ROOT/'ios/App'/(name+'.swift') for name in NAMES]+[ROOT/'weapon_inventory.js',Path(__file__)]
    snapshot={str(p.relative_to(ROOT)):p.read_bytes() for p in paths}
    data=['native/models/animations.clips.bin','native/foot-animation.json','world/peds.json']
    for name in data:assert (ROOT/'local-only/site/game'/name).is_file(),'Owner-local data required: '+name
    with tempfile.TemporaryDirectory(prefix='native-fire-',dir=OUT) as temp:
        folder=Path(temp);sources=[]
        for name in NAMES:
            p=folder/(name+'.swift');p.write_bytes(snapshot['ios/App/'+name+'.swift']);sources.append(str(p))
        main=folder/'main.swift';main.write_text(SWIFT);sources.append(str(main));exe=folder/'verify'
        compile=subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'modules'),*sources,'-o',str(exe)],capture_output=True,text=True)
        (OUT/'compile.log').write_text(compile.stdout+compile.stderr);compile.check_returncode()
        emitted=subprocess.run([str(exe),str(ROOT)],capture_output=True,text=True,check=True)
        (OUT/'emissions.json').write_text(emitted.stdout)
        js=folder/'compare.js';js.write_text(NODE)
        result=subprocess.run(['node',str(js),str(ROOT),str(OUT)],capture_output=True,text=True)
        unchanged=all((ROOT/name).read_bytes()==value for name,value in snapshot.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','output':result.stdout+result.stderr,
                'sourceUnchanged':unchanged,'sourceHashes':{name:hashlib.sha256(value).hexdigest() for name,value in snapshot.items()},
                'localDataHashes':{name:hashlib.sha256((ROOT/'local-only/site/game'/name).read_bytes()).hexdigest() for name in data},
                'limits':['Stationary standing/crouched native fire with continuously ready synthetic magazines',
                          'Real native/CLP emission times; simulated render grouping and bounded20ms receive jitter',
                          'No retail runtime, physical control, FPS, damage, hit geometry or reload-duration claim']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged,'Source changed during test'
        print('PASS real native fire arrival; source unchanged')
if __name__=='__main__':main()
