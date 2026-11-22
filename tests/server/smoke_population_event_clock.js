// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual independent task and producer on authored straight pavements and flat
// geometry. Analytical motion witnesses use the existing speed/acceleration
// contract; they are not original-game timing or population-policy measurements.
const assert=require('node:assert/strict'),path=require('node:path');
const {Pedestrians}=require(process.argv[2]?path.resolve(process.argv[2]):'../../server/population/pedestrians');
const selected=process.argv[3]||'all';let checks=0;
const check=(value,message)=>{assert(value,message);checks++;};
const near=(actual,wanted,message)=>check(Math.abs(actual-wanted)<1e-8,message+': '+actual+' != '+wanted);
const observer=[0,0,13];
function make(){
 const points=[[50,0,13],[1000,0,13]],graph={point:id=>points[id].slice(),neighbors:id=>[{id:id^1,kind:0}],nearest:()=>({id:0,distance:15})};
 const population=new Pedestrians({graph,models:[7],random:()=>0,ground:()=>13,clear:()=>true,maximum:1,perObserver:1});
 population.tick(0,[observer]);const actor=[...population.actors.values()][0];
 check(actor&&actor.position[0]===50,'Authored initial task missing');actor.speed=1.1;
 return{population,actor};
}
function run(event,end,hz,explicit=false){
 const value=make(),ticks=[];for(let n=1;n*1000/hz<end-1e-7;n++)ticks.push(n*1000/hz);ticks.push(end);
 const when=event==='expiry'?0:37,timeline=[...new Set([...ticks,when])].sort((a,b)=>a-b);
 for(const at of timeline){
  if(at===when){
   if(explicit)value.population.tick(at,[observer]);
   const from=[48,0,13];
   if(['flee','expiry'].includes(event))value.population.flee(value.actor,from,at);
   else if(event==='gunshot')value.population.gunshot(from,at);
   else check(value.population.damage('p'+value.actor.id,event==='death'?100:10,{weapon:22,piece:3,from,now:at}),'Valid event rejected');
  }
  if(ticks.includes(at))value.population.tick(at,[observer]);
 }
 return value;
}
if(selected==='all'||selected==='events'){
 for(const event of ['flee','gunshot','injury','death'])for(const hz of [20,30,60,120])for(const explicit of [false,true]){
  const {population,actor}=run(event,200,hz,explicit),dead=event==='death';
  const wanted=dead?50+1.1*.037:50+1.1*.2+2*.163*.163;
  near(actor.position[0],wanted,event+' must settle previous movement before the event at '+hz+'Hz explicit='+explicit);
  near(actor.speed,dead?0:1.1+4*.163,event+' velocity advanced outside its own task interval');
  check(actor.health===(dead?0:event==='injury'?90:100),'Event health changed');
  const packets=population.packets({},actor.position,200),packet=packets.find(p=>p[0]===10);check(!!packet,'Actual free-goal producer missing');
  const at=(packet[1]&128?3:2)+4;check(Math.abs(packet.readInt32BE(at+5)/1000-wanted)<=.000501,'Published position differs from the actual settled task');
  if(dead)check((packet.readUInt16BE(at+2)>>12&9)===9&&packet[at+19]===0&&packet[at+20]===0,'Terminal packet retains live movement');
 }
}
if(selected==='all'||selected==='expiry'){
 // 0.525s acceleration from1.1 to3.2,5.475s held running,0.1s
 // deceleration after the exact6s deadline. No step may borrow the new task.
 const wanted=50+(1.1+3.2)*.525/2+3.2*5.475+(3.2+2.8)*.1/2;
 for(const hz of [20,30,60,120]){
  const {actor}=run('expiry',6100,hz);
  near(actor.position[0],wanted,'Panic expiry shifts movement at '+hz+'Hz');near(actor.speed,2.8,'Panic expiry velocity at '+hz+'Hz');
  check(!(actor.flags&4)&&actor.desiredSpeed===1.1,'Expired panic task retained its sprint intention');
 }
}
if(selected==='all'||selected==='clock'){
 const value=make();value.population.tick(100,[observer]);const before=value.actor.position[0];
 value.population.tick(50,[observer]);value.population.tick(100,[observer]);near(value.actor.position[0],before,'Backward/repeated clock replayed elapsed movement');
 check(value.population.lastTime===100,'Simulation clock regressed');
 const snapshot=JSON.stringify(value.actor),clock=value.population.lastTime;
 check(!value.population.damage('p'+value.actor.id,NaN,{from:observer,now:137,weapon:22}),'Invalid damage accepted');
 check(snapshot===JSON.stringify(value.actor)&&value.population.lastTime===clock,'Invalid damage changed the simulation clock');
 const stale={...value.actor};value.population.flee(stale,observer,137);check(snapshot===JSON.stringify(value.actor)&&value.population.lastTime===clock&&stale.flags===value.actor.flags,'Retired actor changed the shared event clock');
 value.population.flee(value.actor,observer,37);check(value.actor.panicUntil===6100,'Backward event backdated its task deadline');
 value.population.tick(150,[observer]);near(value.actor.speed,1.3,'Repeated event time advanced movement twice');
}
if(selected==='all'||selected==='shared'){
 const value=make(),other={...value.actor,id:2,position:[50,10,13],goal:[1000,10]};value.population.actors.set(2,other);
 value.population.damage('p'+value.actor.id,100,{from:observer,now:37,weapon:24});
 near(other.position[0],50+1.1*.037,'Event did not settle the other shared actor');
 value.population.tick(200,[observer]);near(other.position[0],50+1.1*.2,'Another actor inherited the event interval twice');
 near(value.actor.position[0],50+1.1*.037,'Death moved after its event boundary');
 value.population.tick(10000,[observer]);check(other.position[0]-(50+1.1*.2)<=1.1*.5+1e-8,'Existing catch-up cap was removed');
}
if(selected==='all'||selected==='junction'){
 // Arrive at the authored junction31.25ms into a100ms update, before
 // panic expires at60ms. A later publication cannot choose the calm turn
 // for that earlier arrival. Lower branch is the deterministic calm choice.
 for(const split of [false,true]){
  const points=[[50,0,13],[51,0,13],[52,1,13],[52,-1,13]],graph={point:id=>points[id].slice(),nearest:()=>({id:0,distance:0}),neighbors:id=>id===0?[{id:1,kind:0}]:id===1?[{id:3,kind:0},{id:2,kind:0},{id:0,kind:0}]:[{id:1,kind:0}]};
  const population=new Pedestrians({graph,models:[7],random:()=>0,ground:()=>13,clear:()=>true,maximum:1,perObserver:1});population.tick(0,[observer]);
  const actor=[...population.actors.values()][0];Object.assign(actor,{position:[50.9,0,13],goal:[51,0],speed:3.2,desiredSpeed:3.2,flags:4,threat:[50,-10,13],panicUntil:60});
  if(split)population.tick(50,[observer]);population.tick(100,[observer]);
  check(actor.to===2&&actor.position[1]>0,'Junction borrowed its later calm state for an earlier flee arrival');
 }
}
console.log('PASS population event clocks: '+checks+' actual-task/producer checks with authored geometry and analytical schedule witnesses; no rendered or retail timing acceptance');
