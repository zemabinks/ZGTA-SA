// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual shared task and packet owners; authored road, wall clock and static
// clearance. No original resources, App, device or retail timing comparison.
const assert=require('node:assert/strict'),path=require('node:path');
const root=process.argv[2]?path.resolve(process.argv[2]):path.resolve(__dirname,'../..');
const {Traffic}=require(path.join(root,'server/population/traffic'));
const {TrafficRoads}=require(path.join(root,'server/population/traffic_roads')),{crc32}=require(path.join(root,'server/population/pedestrian_paths'));
const {square}=require(path.join(root,'tests/server/traffic_fixture'));
let checks=0;const check=(value,message)=>{assert(value,message);checks++;};
const equal=(a,b,message)=>{assert.deepEqual(a,b,message);checks++;};
function create(start=1000){
 const b=square(),graph=new TrafficRoads(b,crc32(b));
 const t=new Traffic({graph,models:[{id:410,length:4,width:2,colors:[[2,3]]}],ground:()=>13,clear:()=>true,random:()=>.1,maximum:1,perObserver:1,speeds:[8,8,8,8]});
 t.tick(start,[[0,0,13]]);check(t.actors.size===1,'No source-owned traffic actor on the authored graph');return t;
}
function state(t){return structuredClone([...t.actors.values()].map(a=>({id:a.id,generation:a.generation,state:a.state,pose:a.pose,lastObserved:a.lastObserved,blockedSince:a.blockedSince})));}
function packet(t,now){return t.packets({},[0,0,13],now)[0];}
for(const start of [0,1000,4294967200]){
 const a=create(start),b=create(start),at=start+237;a.tick(at,[[0,0,13]]);b.tick(at,[[0,0,13]]);
 const old=state(b),sample=b.sampleTime,remainder=b.remainder,bytes=packet(b,at);
 for(const back of [at-1,at-49,start,at,at-5]){
  b.tick(back,[[0,0,13]]);
  equal(b.sampleTime,sample,'Backward traffic tick rewound the published simulation sample');
  check(Math.abs(b.remainder-remainder)<1e-12,'Backward traffic tick discarded its unconsumed fraction');
  equal(state(b),old,'Repeated/backward observation changed the shared physical lifetime');
  equal(packet(b,at),bytes,'Event publication rewrote the actual compact traffic sample');
 }
 b.tick(at,[[0,0,13]]);equal(state(b),state(a),'Clock rebound consumed shared traffic movement twice');
 a.tick(start+300,[[0,0,13]]);b.tick(start+300,[[0,0,13]]);
 equal(state(b),state(a),'Forward recovery diverged from the uninterrupted traffic clock');
 equal(packet(b,start+300),packet(a,start+300),'Observers disagree after backward-clock recovery');
}
const intervals=[[10],[25],[50],[100],[200],[500],[17,83,40,60]];
function run(schedule,inject){
 const t=create();let elapsed=0,n=0;
 while(elapsed<20000){
  elapsed=Math.min(20000,elapsed+schedule[n++%schedule.length]);const at=1000+elapsed;t.tick(at,[[0,0,13]]);
  if(inject)for(const back of [at-1,at-137,1000,at])t.tick(back,[[0,0,13]]);
 }
 return t;
}
const reference=run([50],false);
for(const schedule of intervals){
 const subject=run(schedule,true);equal(state(subject),state(reference),'Backward samples changed cadence-independent road tasks');
 equal(packet(subject,21000),packet(reference,21000),'Compact publication changed across injected clock schedules');
}
const bounded=create(),control=create();bounded.tick(1237,[[0,0,13]]);control.tick(1237,[[0,0,13]]);
bounded.tick(1100,[[0,0,13]]);bounded.tick(10000,[[0,0,13]]);control.tick(10000,[[0,0,13]]);
equal(state(bounded),state(control),'Backward sample changed the retained half-second catch-up policy');
check(Math.abs(bounded.remainder-control.remainder)<1e-12,'Catch-up lost its pending fraction');
check(bounded.sampleTime===control.sampleTime,'Catch-up relabeled the fixed-step time');
const before=state(bounded),time=bounded.previousTime,remainder=bounded.remainder;
for(const invalid of [-1,NaN,Infinity,10000.5,Number.MAX_SAFE_INTEGER+1]){
 assert.throws(()=>bounded.tick(invalid,[[0,0,13]]));checks++;
 equal(state(bounded),before,'Invalid clock changed a shared actor');
 equal(bounded.previousTime,time,'Invalid clock changed the sample owner');
 equal(bounded.remainder,remainder,'Invalid clock changed fixed-step debt');
}
console.log('PASS monotonic shared traffic clock '+checks+' checks; authored graph/time, actual task/packet owners; no App or retail claim');
