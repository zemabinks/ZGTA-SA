// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Authored pavement islands and explicit flat/blocked geometry. Exercise the
// actual task and packet producers without original data or rendered clients.
const assert=require('node:assert/strict'),path=require('node:path');
const {Pedestrians}=require(process.argv[2]?path.resolve(process.argv[2]):'../../server/population/pedestrians');
let checks=0;const check=(value,message)=>{assert(value,message);checks++;};
const initial=[0,0,13],distant=[180,0,13],watching=[60,0,13];
function make(){
 let blocked=false;
 const points=[[50,0,13],[60,0,13],[220,0,13],[230,0,13]];
 const graph={point:id=>points[id].slice(),neighbors:id=>[{id:id^1,kind:0}],nearest:query=>{
  const rows=points.map((point,id)=>({id,distance:Math.hypot(...point.map((v,i)=>v-query[i]))}));
  rows.sort((a,b)=>a.distance-b.distance);return rows[0].distance<=18?rows[0]:null;
 }};
 const population=new Pedestrians({graph,models:[14],ground:()=>13,clear:()=>!blocked,
  random:()=>0,maximum:1,perObserver:1});
 population.tick(0,[initial]);const actor=[...population.actors.values()][0];
 check(actor&&actor.position[0]===50,'Fixture did not spawn the actual initial task');
 return{population,actor,block:()=>{blocked=true;}};
}
const first=make(),peer={};
check(first.population.packets(peer,initial,0).some(p=>p[0]===10),'Initial observer missed the free-goal packet');
first.block();first.population.tick(100,[distant]);
const gone=first.population.packets(peer,distant,100);
check(gone.length===1&&gone[0][0]===8&&gone[0].readUInt16BE(2)===first.actor.id,'Leaving interest failed to remove the exact client actor');
for(let at=200;at<=3400;at+=100)first.population.tick(at,[distant]);
check(!first.population.actors.has(first.actor.id),'Invisible pedestrians permanently occupied the shared spawn budget');
const replacement=[...first.population.actors.values()][0];
check(replacement&&replacement.id!==first.actor.id&&replacement.position[0]>=220,'Released capacity did not populate the new observer area');
check(first.population.packets(peer,distant,3400).some(p=>p[0]===10),'Replacement was not actually published');
check(first.population.actors.size===1,'Streaming exceeded the configured shared population budget');

const shared=make(),otherPeer={};shared.block();
for(let at=100;at<=6000;at+=100)shared.population.tick(at,[distant,watching]);
check(shared.population.actors.get(shared.actor.id)===shared.actor,'One observer removed another observer\'s visible actor');
check(shared.population.packets(otherPeer,watching,6000).some(p=>p[0]===10),'Second observer lost the shared actor packets');
shared.population.forget(otherPeer);
for(let at=6100;at<=9400;at+=100)shared.population.tick(at,[distant]);
check(!shared.population.actors.has(shared.actor.id),'Last observer leaving did not expire the hidden lifetime');

// The publication boundary is strict. An untransmitted actor at exactly the
// cutoff must not receive a retention refresh. A point just inside retains it.
for(const offset of [109.999,110,110.001,139.999]){
 const value=make();value.block();const position=[50+offset,0,13];
 const visible=value.population.packets({},position,0).some(p=>p[0]===10);
 check(visible===(offset<110),'Unexpected publication boundary');
 for(let at=100;at<=3300;at+=100)value.population.tick(at,[position]);
 check(value.population.actors.has(value.actor.id)===visible,'Retention and publication use different distance boundaries');
}

// Brief streamout keeps the exact existing lifetime; new interest restores it.
const brief=make();brief.block();brief.population.tick(100,[distant]);brief.population.tick(2900,[watching]);
check(brief.population.actors.get(brief.actor.id)===brief.actor,'Brief absence destroyed a still-retained actor');
check(brief.population.packets({},watching,2900).some(p=>p[0]===10),'Re-entering interest did not restore packets');

// Visible death keeps its corpse lifetime; hidden death releases capacity.
for(const visible of [false,true]){
 const value=make();value.block();
 check(value.population.damage('p'+value.actor.id,100,{from:watching,now:1,weapon:22}),'Fixture did not enter real death task');
 const observers=[visible?watching:distant];
 for(let at=100;at<=3300;at+=100)value.population.tick(at,observers);
 check(value.population.actors.has(value.actor.id)===visible,'Death used a contradictory observation lifetime');
 if(visible){value.population.tick(20100,observers);check(!value.population.actors.has(value.actor.id),'Visible corpse ignored its terminal lifetime');}
}

for(const hz of [20,30,60,120]){
 const value=make();value.block();
 for(let n=1;n<=hz*4;n++)value.population.tick(n*1000/hz,[distant]);
 check(!value.population.actors.has(value.actor.id),'Hidden lifetime depends on server tick rate');
 check(value.population.actors.size===1,'New area did not repopulate after timeout');
}
console.log('PASS population observation lifetime '+checks+' checks; authored geometry and actual server tasks/packets, no App or retail claim');
