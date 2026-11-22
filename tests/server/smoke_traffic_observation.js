// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Authored roads and static clearance boundary; actual manager, publication
// and observer lifetimes. No original resources, App or retail measurement.
const assert=require('node:assert/strict'),path=require('node:path');
const {Traffic}=require(process.argv[2]?path.resolve(process.argv[2]):'../../server/population/traffic');
const {TrafficRoads}=require('../../server/population/traffic_roads'),{crc32}=require('../../server/population/pedestrian_paths');
const {square}=require('./traffic_fixture');const bytes=square(),graph=new TrafficRoads(bytes,crc32(bytes));
let checks=0;const check=(value,message)=>{assert(value,message);checks++;};
const initial=[0,0,13],distant=[-90,24,13],watching=[60,24,13];
function make(){
 let blocked=false;const traffic=new Traffic({graph,models:[{id:410,length:4,width:2,colors:[[2,3]]}],ground:()=>13,
  clear:(from,to)=>!blocked||(from[0]<30&&to[0]<30),random:()=>.1,maximum:1,perObserver:1});
 traffic.tick(0,[initial]);const actor=[...traffic.actors.values()][0];
 check(actor&&Math.hypot(actor.pose.position[0]-40,actor.pose.position[1]-24)<.01,'Fixture did not use its intended initial road sample');
 return{traffic,actor,block:()=>{blocked=true;}};
}
const first=make(),peer={};
check(first.traffic.packets(peer,initial,0).some(p=>p[0]===4),'Initial client never received its actual traffic base');
first.block();first.traffic.tick(100,[distant]);
check(first.traffic.packets(peer,distant,100).some(p=>p[0]===5),'Moving outside the publication radius did not retire client interest');
for(let at=200;at<=6000;at+=100)first.traffic.tick(at,[distant]);
check(!first.traffic.actors.has(first.actor.id),'Unseen stopped traffic permanently occupied the shared population budget');
check(first.traffic.actors.size===1&&first.traffic.packets(peer,distant,6000).some(p=>p[0]===4),'Retired unseen traffic did not release capacity for an observable road vehicle');
const shared=make(),otherPeer={};shared.block();
for(let at=100;at<=6000;at+=100)shared.traffic.tick(at,[distant,watching]);
check(shared.traffic.actors.has(shared.actor.id),'A second observer lost its still-visible shared traffic lifetime');
check(shared.traffic.packets(otherPeer,watching,6000).some(p=>p[0]===4),'Second observer did not retain shared traffic publication');
shared.traffic.forget(otherPeer);
for(let at=6100;at<=11200;at+=100)shared.traffic.tick(at,[distant]);
check(!shared.traffic.actors.has(shared.actor.id),'Last observer leaving did not start the unseen lifetime timeout');
console.log('PASS traffic observation lifetime '+checks+' checks; authored world and actual task/publication owners, not rendered or retail acceptance');
