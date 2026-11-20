// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const assert=require('node:assert/strict');
const {Pedestrians}=require('../../server/population/pedestrians');
let checks=0;const check=(value,text)=>{assert(value,text);checks++;};
// Authored connected square graph and explicit geometry boundary. No original
// arrays, retail population policy or server mesh acceptance is implied.
const points=[[0,0,13],[50,0,13],[50,50,13],[0,50,13]];
const graph={point:id=>points[id].slice(),neighbors:id=>[{id:(id+1)%4,kind:0},{id:(id+3)%4,kind:0}],
 nearest(query){let id=0;for(let n=1;n<4;n++)if(Math.hypot(...query.map((v,i)=>v-points[n][i]))<Math.hypot(...query.map((v,i)=>v-points[id][i])))id=n;return{id,distance:1};}};
let blocked=false,grounded=true;const population=()=>new Pedestrians({graph,models:[7,14],random:()=>0.1,ground:()=>grounded?13:null,clear:()=>!blocked,maximum:4,perObserver:2});
const p=population();p.tick(0,[[0,0,13]]);
check(p.actors.size===1,'Actual task failed to spawn on graph');
const actor=[...p.actors.values()][0],origin=actor.position.slice();
check(actor.skin===7&&actor.node===1,'Model/graph selection');
p.tick(200,[[0,0,13]]);check(Math.hypot(...actor.position.map((v,i)=>v-origin[i]))>0.01,'NPC did not traverse graph');
const near=actor.position.slice();check(p.packets('one',near,200).some(packet=>packet[0]===10),'Separate free-goal channel missing');
check(p.packets('two',near,200).length===2,'Second observer did not share actual actor');
const more=p.packets('two',near,200).find(packet=>packet[0]===11);
check(more.readUInt16BE((more[1]&128?3:2)+8)===0,'Calm actor invented a foe identity');
const gone=p.packets('one',[1000,1000,13],201);check(gone.length===1&&gone[0][0]===8,'Interest streamout missing');
check(p.packets('two',near,201).every(packet=>packet[0]!==8),'One observer removed another observer actor');
p.forget('one');check(!p.interest.has('one'),'Disconnected interest retained');
const before=actor.position.slice();blocked=true;p.tick(400,[[0,0,13]]);
check(actor.flags&2&&actor.speed===0&&actor.position.every((v,i)=>v===before[i]),'Obstacle wait failed');
// Inspect the actual producer bytes. A wait flag alone does not stop the
// archived/native free-goal predictor from accelerating toward its goal.
const wanted=(packet)=>packet[(packet[1]&128?3:2)+4+20];
const waiting=p.packets('two',actor.position,400).find(packet=>packet[0]===10);
check(wanted(waiting)===0,'Blocked actor still publishes client acceleration');
check(actor.desiredSpeed===1.1,'Wire stop lost the server recovery intention');
blocked=false;p.tick(600,[[0,0,13]]);check(!(actor.flags&2)&&actor.speed>0,'Obstacle recovery failed');
check(wanted(p.packets('two',actor.position,600).find(packet=>packet[0]===10))>0,'Recovery did not restore client movement');
p.gunshot(actor.position.map((v,i)=>v+(i===0?2:0)),600);
check(actor.flags&4&&actor.desiredSpeed===3.2,'Gunshot did not enter flee task');
check(!p.get('1')&&!p.get('p01')&&!p.get('p65536')&&p.get('p'+actor.id)===actor,'NPC target namespace ambiguous');
check(!p.damage('p'+actor.id,NaN,{from:near,now:700}),'Invalid damage admitted');
check(p.damage('p'+actor.id,18,{from:near,now:700,weapon:22}),'Authoritative injury not applied');
check(actor.health===82&&actor.hitCounter===1&&actor.hitWeapon===22,'Authoritative injury metadata');
check(p.damage('p'+actor.id,100,{from:near,now:800,weapon:24}),'Authoritative death not applied');
check(actor.health===0&&(actor.flags&9)===9&&actor.speed===0,'Death continued movement');
check(!p.damage('p'+actor.id,100,{from:near,now:900,weapon:24}),'Dead actor damaged twice');
p.tick(20900,[[0,0,13]]);check(!p.actors.has(actor.id),'Corpse lifetime failed');
const noGround=population();grounded=false;noGround.tick(0,[[0,0,13]]);check(noGround.actors.size===0,'Missing collision invented ground');grounded=true;
const empty=population();for(let n=0;n<20;n++)empty.tick(n*250,[]);check(empty.actors.size===0,'NPCs invented without observers');
const retired=population();retired.tick(0,[[0,0,13]]);retired.tick(3100,[]);check(retired.actors.size===0,'Unobserved population did not retire');
const samples=[];
for(const hz of [20,30,60,120]){
 const value=population();value.tick(0,[[0,0,13]]);const target=[...value.actors.values()][0];
 for(let n=1;n<=hz;n++)value.tick(n*1000/hz,[[0,0,13]]);
 samples.push(target.position);
}
for(const sample of samples)check(Math.hypot(...sample.map((v,i)=>v-samples[0][i]))<0.000001,'Server acceleration depends on tick rate');
console.log('PASS independent population tasks: '+checks+' authored checks; original density/social/traffic/police AI and real geometry acceptance remain separate');
