#!/usr/bin/env node
'use strict';
// Synthetic transport tests. No original game assets or listening service.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),Module=require('node:module');
const {create}=require('../../weapon_inventory');
const ids=[22,28,37,41,42];
const catalog={items:ids.map(id=>({id,name:'Transport fixture',slot:id,ammo:9999,capacity:9999,price:0})),shops:[]};
const timingDefinitions=ids.map(id=>({id,use:id>=37?'stream':'gun',continuous:id>=37,
  loop:{every:id===22?.3:id===28?.12:.02}}));
const options={timingDefinitions},start=1_700_000_000_000;
const player=id=>({health:100,inventory:{selected:id,weapons:{[id]:{clip:9999,rest:0}}}});
let checks=0;
function check(value,message){checks++;assert(value,message);}
function grouped(factory){
  let emissions=0,rejections=0,cases=0;
  for(const id of ids)for(const hz of [15,30,60,120,144])for(const jitter of [false,true]){
    const store=factory(catalog,options),p=player(id),interval=store.cadence(id).intervalMs;
    let previous=0,sequence=0;cases++;
    for(let emitted=1000/30;emitted<=20000;emitted+=interval){
      const display=Math.ceil(emitted*hz/1000-1e-9)/hz*1000;
      const delay=jitter?[20,0,10,3,16,7,19,1][Math.ceil(display*hz/1000)%8]:0;
      const arrival=Math.max(previous,Math.round(display+delay));previous=arrival;emissions++;
      if(!store.acceptShot(p,id,start+arrival,{sequence:++sequence}).ok)rejections++;
    }
  }
  return {cases,emissions,rejections};
}
const traffic=grouped(create);
check(traffic.rejections===0,'Canonical fire was rejected by grouped frames or bounded20ms jitter');

for(const id of ids){
  const store=create(catalog,options),p=player(id),timing=store.cadence(id),capacity=timing.capacity;
  check(capacity===(id>=37?5:2),'Unexpected transport burst bound');
  for(let n=0;n<capacity;n++)check(store.acceptShot(p,id,start,{sequence:n}).ok,'Fresh catch-up unavailable');
  const clip=p.inventory.weapons[id].clip,revision=p.inventory.revision;
  check(!store.acceptShot(p,id,start,{sequence:capacity}).ok,'Burst limit exceeded');
  check(p.inventory.weapons[id].clip===clip&&p.inventory.revision===revision,'Rejected burst spent inventory');
  check(!store.acceptShot(p,id,start,{sequence:capacity-1}).ok,'Replay accepted');
  check(!store.acceptShot(p,id,start,{sequence:capacity,sequenceScope:{}}).ok,'New connection scope reset rate credit');
  check(!store.acceptShot(p,id,start-1000,{sequence:capacity}).ok,'Backward clock refilled rate credit');
  check(store.acceptShot(p,id,start+timing.intervalMs,{sequence:capacity}).ok,'Rejected uncommitted request could not use later credit');
  check(!store.acceptShot(p,id,start+timing.intervalMs,{sequence:capacity+1}).ok,'One interval supplied multiple fresh tokens');

  // A restart must honor the persisted last-shot timestamp, not grant a new
  // initial burst. Native reconnects likewise retain the same player bucket.
  const restarted=create(catalog,options),saved=structuredClone(p);
  check(!restarted.acceptShot(saved,id,start+timing.intervalMs,{sequence:0}).ok,'Restart granted free credit');
  check(restarted.acceptShot(saved,id,start+2*timing.intervalMs,{sequence:0}).ok,'Persisted cooldown never completed');

  const pressure=create(catalog,options),attacker=player(id);let accepted=0;
  // An attempted event every millisecond cannot raise the sustained rate.
  for(let ms=0;ms<=10000;ms++){
    if(pressure.acceptShot(attacker,id,start+ms,{sequence:ms}).ok)accepted++;
    check(accepted<=capacity+Math.floor((ms+1e-5)/timing.intervalMs),'Sustained canonical rate exceeded');
  }
}
{
  const store=create(catalog,options),p=player(28);
  p.inventory.weapons[22]={clip:9999,rest:0};
  for(let s=0;s<2;s++)check(store.acceptShot(p,28,start,{sequence:s}).ok,'Burst fixture');
  p.inventory.selected=22;
  check(!store.acceptShot(p,22,start,{sequence:2}).ok,'Weapon switch manufactured credit');
}

// Historical negative control: restore only the old initial credit and stream
// capacity in our own module. The identical traffic must expose the defect.
const filename=path.join(require('node:path').resolve(__dirname, '../..'),'weapon_inventory.js'),source=fs.readFileSync(filename,'utf8');
const seed='Math.max(0,now-inventory.lastShotAt)/interval):timing.capacity};';
const capacityMarker='capacity:stream?5:frameCredit';
check(source.includes(seed)&&source.includes(capacityMarker),'Historical control markers changed; review this probe');
const old=new Module(filename,module);old.filename=filename;old.paths=module.paths;
old._compile(source.replace(seed,'Math.max(0,now-inventory.lastShotAt)/interval):1};').replace(capacityMarker,'capacity:stream?4:2'),filename);
const before=grouped(old.exports.create);
check(before.rejections>0,'Historical receive-time failure was not reproduced');
console.log(`PASS: ${checks} transport checks; ${traffic.cases} grouped-frame/jitter cases and ${traffic.emissions} synthetic emissions without rejection; historical control rejected${before.rejections}. Bounded2-to-5 bursts, sustained rate, replay, switch, reconnect, restart and backward clock.`);
