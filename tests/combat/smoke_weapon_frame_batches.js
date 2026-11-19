#!/usr/bin/env node
'use strict';
// AGPL-3.0-only. Independently authored cadence data; no game assets/services.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=require('node:path').resolve(__dirname, '../..'),args=process.argv.slice(2),historical=args[0]==='--historical-module';
assert(args.length===0 || historical && args.length===2,'Usage: node tests/combat/smoke_weapon_frame_batches.js [--historical-module /absolute/weapon_inventory.js]');
const source=fs.readFileSync(historical ? path.resolve(args[1]):path.join(root,'weapon_inventory.js'));
// Copy only independent module source. Its optional default data lookup cannot
// see owner catalogues; every tested catalogue/profile below is authored here.
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-weapon-frame-batches-'));
let checks=0;
const check=(value,message)=>{checks++;assert(value,message);};
const epoch=1_700_000_000_000;
try {
  const modulePath=path.join(temporary,'weapon_inventory.js');fs.writeFileSync(modulePath,source);
  const {create}=require(modulePath);
  const definitions=[
    {id:101,use:'gun',loop:{every:.02}},
    {id:102,use:'gun',loop:{every:.04}},
    {id:103,use:'gun',loop:{every:.08}},
    {id:104,use:'gun',loop:{every:.12}},
    {id:105,use:'gun',loop:{every:.30}},
    {id:106,use:'gun',twin:true,loop:{every:.04}},
    {id:107,use:'stream',continuous:true,loop:{every:.3}},
  ];
  const catalogue={items:definitions.map(p=>({id:p.id,name:'Authored fixed-tick fixture',ammo:9999,capacity:9999,price:0,slot:p.id,
    fire:p.use==='stream'?'AREA_EFFECT':'INSTANT_HIT'})),shops:[]};
  const store=()=>create(catalogue,{timingDefinitions:definitions});
  const player=id=>({health:100,inventory:{selected:id,weapons:{[id]:{clip:9000,rest:0}}}});
  const cases=[];
  for(const definition of definitions)for(const hz of [15,30,60,120]) {
    const api=store(),p=player(definition.id),gap=api.cadence(definition.id).intervalMs;
    let emitted=0,accepted=0,rejected=0,maxBatch=0,batch=0,lastArrival=-1;
    for(let logical=137;logical<30_000;logical+=gap) {
      const arrival=Math.round(Math.ceil(logical/(1000/hz)-1e-9)*(1000/hz));
      if(arrival===lastArrival)batch++;else{batch=1;lastArrival=arrival;}
      maxBatch=Math.max(maxBatch,batch);emitted++;
      const result=api.acceptShot(p,definition.id,epoch+arrival,{sequence:emitted});
      if(result.ok)accepted++;else rejected++;
      if(!historical)check(result.ok,`Legitimate ${gap}ms ${definition.use} event rejected in ${hz}Hz display batch`);
    }
    check(p.inventory.weapons[definition.id].clip===9000-accepted,'Ammo does not equal accepted events');
    cases.push({id:definition.id,hz,intervalMs:gap,capacity:api.cadence(definition.id).capacity,emitted,accepted,rejected,maxBatch});
  }
  if(historical) {
    check(cases.some(c=>c.id===101&&c.hz===15&&c.rejected>0),'Historical low-FPS gun defect was not reproduced');
    check(cases.some(c=>c.id===101&&c.hz===30&&c.rejected>0),'Historical 30Hz phase-credit defect was not reproduced');
    check(cases.filter(c=>c.id===101&&c.hz>=60).every(c=>c.rejected===0),'Unbatched historical negative failed');
    check(cases.filter(c=>c.id===107).every(c=>c.rejected===0),'Existing stream policy negative failed');
  } else {
    const api=store();
    check(api.cadence(101).capacity===5 && api.cadence(106).capacity===5,'Fast gun/twin batch credit missing');
    check(api.cadence(102).capacity===3,'Intermediate cadence phase credit missing');
    check([103,104,105].every(id=>api.cadence(id).capacity===2),'Ordinary gun credit changed');
    check(api.cadence(107).capacity===5,'Existing stream credit changed');
    for(const definition of definitions) {
      const bounded=store(),p=player(definition.id),cadence=bounded.cadence(definition.id);
      let accepted=0,sequence=0;
      for(let n=0;n<40;n++)accepted+=Number(bounded.acceptShot(p,definition.id,epoch,{sequence:++sequence}).ok);
      check(accepted===cadence.capacity && accepted<=5,'Instant burst is unbounded');
      const initial=accepted;
      for(let ms=1;ms<=2000;ms++)accepted+=Number(bounded.acceptShot(p,definition.id,epoch+ms,{sequence:++sequence}).ok);
      check(accepted<=initial+Math.floor(2000/cadence.intervalMs),'Display credit changed sustained refill rate');
      check(p.inventory.weapons[definition.id].clip===9000-accepted,'Rejected packets spent ammunition');
      const before=p.inventory.weapons[definition.id].clip;
      check(!bounded.acceptShot(p,definition.id,epoch+2000,{sequence:sequence}).ok,'Duplicate sequence reapplied');
      check(!bounded.acceptShot(p,definition.id,NaN,{sequence:sequence+1}).ok,'Nonfinite server clock accepted');
      check(!bounded.acceptShot(p,definition.id,epoch-1000,{sequence:sequence+1,elapsed:1e9,timestamp:epoch+1e9}).ok,'Rollback/client claimed time granted credits');
      check(p.inventory.weapons[definition.id].clip===before,'Invalid replay/clock requests spent ammo');
    }
    const api2=store(),p=player(101);p.inventory.weapons[105]={clip:100,rest:0};
    let seq=0;
    for(let n=0;n<5;n++)check(api2.acceptShot(p,101,epoch,{sequence:++seq}).ok,'Initial bounded credit missing');
    for(let n=0;n<12;n++) {
      p.inventory.selected=n%2?101:105;
      check(!api2.acceptShot(p,p.inventory.selected,epoch,{sequence:++seq}).ok,'Switching granted free cadence credit');
    }
    p.inventory.selected=101;p.inventory.reload={weapon:101,until:epoch+1000};
    check(!api2.acceptShot(p,101,epoch+100,{sequence:++seq}).ok,'Reload permitted shot');
    p.inventory.reload=null;p.inventory.weapons[101].clip=0;
    check(!api2.acceptShot(p,101,epoch+100,{sequence:++seq}).ok,'Empty clip permitted shot');
    p.inventory.weapons[101].clip=5;p.health=0;
    check(!api2.acceptShot(p,101,epoch+100,{sequence:++seq}).ok,'Death permitted shot');
    p.health=100;p.passive=true;
    check(!api2.acceptShot(p,101,epoch+100,{sequence:++seq}).ok,'Passive mode permitted shot');
    p.passive=false;
    check(!api2.acceptShot(p,101,epoch+100,{sequence:true}).ok,'Boolean sequence accepted');
    const scoped=store(),q=player(104),oldPeer={},newPeer={};
    check(scoped.acceptShot(q,104,epoch,{sequence:1,sequenceScope:oldPeer}).ok,'First peer shot missing');
    check(scoped.acceptShot(q,104,epoch+120,{sequence:1,sequenceScope:newPeer}).ok,'New peer inherited old sequence floor');
    check(!scoped.acceptShot(q,104,epoch+240,{sequence:1,sequenceScope:oldPeer}).ok,'Old peer duplicate gained authority');
  }
  const directory=path.join(root,'local-only/research/weapon-frame-batches-115');fs.mkdirSync(directory,{recursive:true});
  const report={status:historical?'HISTORICAL_DEFECT_REPRODUCED':'PASS',checks,cases,
    sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),
    testSHA256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),
    limits:['Authored logical event schedules and actual independent inventory policy; no original assets, animation runtime, network or device',
      'One bounded15Hz transport window plus phase credit; arbitrary longer stalls are not made unlimited',
      'Maximum five immediate credits; sustained server-time refill and all ownership/reload/ammo checks retained']};
  fs.writeFileSync(path.join(directory,historical?'historical-report.json':'report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(`${report.status}: ${checks} weapon frame-batch checks / ${cases.length} rate/frame cases`);
} finally {fs.rmSync(temporary,{recursive:true,force:true});}
