// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Authored route/clock replay of the actual server task. No original navigation
// arrays, collision mesh, client rendering or retail AI are supplied.
const assert=require('node:assert/strict'),path=require('node:path');
const {Pedestrians}=require(path.resolve(process.argv[2]||path.join(__dirname,'../../server/population/pedestrians.js')));
let checks=0;function check(value,text){assert(value,text);checks++;}
function graph(side,duplicate=false){
 const points=duplicate?[[0,0,13],[0,0,13]]:[[0,0,13],[side,0,13],[side,side,13],[0,side,13]];
 return{point:id=>points[id].slice(),nearest:()=>({id:0,distance:0}),neighbors:id=>[{id:(id+1)%points.length,kind:0}]};
}
function make(side){return new Pedestrians({graph:graph(side),models:[14],ground:()=>13,clear:()=>true,random:()=>.1,maximum:1,perObserver:1});}
function run(side,steps,duration){
 const p=make(side);p.tick(0,[[0,0,13]]);let elapsed=0,index=0;
 while(elapsed<duration-1e-8){elapsed=Math.min(duration,elapsed+steps[index++%steps.length]);p.tick(elapsed*1000,[[0,0,13]]);}
 return[...p.actors.values()][0];
}
function square(side,distance){
 const phase=(distance%(4*side)+4*side)%(4*side);
 if(phase<side)return[phase,0,13];
 if(phase<2*side)return[side,phase-side,13];
 if(phase<3*side)return[3*side-phase,side,13];
 return[0,4*side-phase,13];
}
const schedules=[...[20,30,60,120].map(hz=>[1/hz]),[.011,.039,.2,.04,.31,.1],[.5]];
const samples=[];
for(const side of [.125,1,3.7])for(const duration of [.05,.2,.275,.5,1,2,20]){
 const accelerationTime=Math.min(duration,1.1/4),distance=2*accelerationTime**2+1.1*(duration-accelerationTime),expected=square(side,distance);
 for(let i=0;i<schedules.length;i++){const actor=run(side,schedules[i],duration);
  check(Math.hypot(...actor.position.map((v,n)=>v-expected[n]))<1e-8,'Lost arrival time or cut corner at side '+side+' duration '+duration+' schedule '+i);
  check(Math.abs(actor.speed-Math.min(1.1,4*duration))<1e-10,'Arrival changed velocity');
  check(!(actor.flags&2),'Unobstructed route blocked');
  if(duration===20&&side===1)samples.push({schedule:i,position:actor.position,speed:actor.speed});
 }
}
// Deceleration must also split the corner at the real arrival time. Begin in
// a legitimate existing task state; this is an explicit authored setup.
for(const schedule of schedules){
 const p=make(.125);p.tick(0,[[0,0,13]]);const actor=[...p.actors.values()][0];actor.speed=1.1;actor.desiredSpeed=0;
 let elapsed=0,index=0;while(elapsed<1-1e-8){elapsed=Math.min(1,elapsed+schedule[index++%schedule.length]);p.tick(elapsed*1000,[[0,0,13]]);}
 const expected=square(.125,1.1*1.1/8);
 check(Math.hypot(...actor.position.map((v,n)=>v-expected[n]))<1e-8,'Braking lost time at corner');check(actor.speed===0,'Braking retained speed');
}
// Duplicate XY nodes must terminate within the bounded route budget.
const loop=new Pedestrians({graph:graph(1,true),models:[14],ground:()=>13,clear:()=>true,random:()=>.1,maximum:1,perObserver:1});
loop.tick(0,[[0,0,13]]);loop.tick(500,[[0,0,13]]);check([...loop.actors.values()][0].position.every(Number.isFinite),'Degenerate route produced invalid position');
console.log(JSON.stringify({status:'PASS',checks,samples,scope:'Authored connected routes, acceleration/braking and admitted clock schedules with explicit flat geometry; no original task or retail claim'},null,2));
