// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const assert=require('node:assert/strict'),path=require('node:path');
const {square}=require('./traffic_fixture'),{crc32}=require('../../server/population/pedestrian_paths');
const {TrafficRoads}=require('../../server/population/traffic_roads'),{Traffic}=require(process.argv[2]?path.resolve(process.argv[2]):'../../server/population/traffic');
let checks=0;function check(value,message){assert(value,message);checks++;}
const bytes=square(),graph=new TrafficRoads(bytes,crc32(bytes));
function make(options={}){return new Traffic({graph,models:[{id:410,length:4,width:2,colors:[[2,3]]}],ground:()=>13,clear:()=>true,random:()=>.1,maximum:1,perObserver:1,speeds:[8,8,8,8],...options});}
function run(intervals){
 const traffic=make();traffic.tick(0,[[0,0,13]]);check(traffic.actors.size===1,'No authoritative traffic spawn');
 let elapsed=0,index=0;while(elapsed<20000){elapsed=Math.min(20000,elapsed+intervals[index++%intervals.length]);traffic.tick(elapsed,[[0,0,13]]);}
 return [...traffic.actors.values()][0];
}
const reference=run([50]);
for(const intervals of [[10],[25],[100],[200],[17,83,40,60],[500]]){
 const actor=run(intervals);
 check(Math.hypot(...actor.pose.position.map((v,i)=>v-reference.pose.position[i]))<1e-9,'Observer/publication cadence changed simulation');
 check(actor.state.speed===reference.state.speed&&actor.state.first.link===reference.state.first.link,'Cadence changed physical route/speed');
}
let available=true;const traffic=make({ground:()=>available?13:null});traffic.tick(0,[[0,0,13]]);let actor=[...traffic.actors.values()][0];
check(actor,'Original-style road admission did not create actor');const peer={};
check(!traffic.promotable(peer,actor.id,actor.pose.position),'Unseen traffic could be promoted');
check(traffic.packets(peer,[0,0,13],0).length===1,'Visible traffic not published');
check(traffic.promotable(peer,actor.id,actor.pose.position)===actor,'Visible near traffic promotion missing');
check(!traffic.promotable(peer,actor.id,[10000,0,13]),'Distant traffic could be promoted');
traffic.tick(20,[[0,0,13]]);
const delayed=traffic.packets(peer,[0,0,13],40)[0],prefix=delayed[1]&128?3:2;
check(delayed.readUInt32BE(prefix)===0,'Event publication relabeled an unadvanced physical sample');
const predicted=traffic.poseAt(actor,40);
check(predicted&&predicted.position.every(Number.isFinite),'Materialization cannot sample the actual client presentation time');
check(!traffic.poseAt(actor,600),'Stale actor could be materialized from unbounded prediction');
actor.state.speed=10;actor.state.wanted=10;
check(!traffic.promotable(peer,actor.id,actor.pose.position,20),'Moving traffic lost momentum through a parked-row transfer');
actor.state.speed=0;actor.state.wanted=0;
check(!traffic.retire(actor.id,actor.generation+1),'Stale generation retired replacement');
check(traffic.retire(actor.id,actor.generation),'Current promotion did not retire compact lifetime');
check(traffic.packets(peer,[0,0,13],1)[0][0]===5&&!traffic.interest.has(peer),'Promoted lifetime did not stream out');
let roadBlocked=false;
const blocked=make({clear:()=>!roadBlocked});blocked.tick(0,[[0,0,13]]);actor=[...blocked.actors.values()][0];const original=actor.pose.position.slice();roadBlocked=true;
for(let n=1;n<=20;n++)blocked.tick(n*50,[[0,0,13]]);
check(actor.state.speed===0&&Math.hypot(...actor.pose.position.map((v,i)=>v-original[i]))===0,'Static obstruction crossed by traffic');
const missing=make({ground:()=>null});missing.tick(0,[[0,0,13]]);check(missing.actors.size===0,'Missing world geometry admitted a car');
const reserved=make({reserved:()=>new Set([0,1,2])});reserved.tick(0,[[0,0,13]]);check([...reserved.actors.keys()][0]===3,'Compact ID reused registered source identity');
const lifetime=make();lifetime.tick(0,[[0,0,13]]);actor=[...lifetime.actors.values()][0];lifetime.packets(peer,[0,0,13],0);
check(lifetime.packets(peer,null,1)[0][0]===5,'Interior retained exterior traffic');
lifetime.packets(peer,[0,0,13],2);lifetime.forget(peer);check(!lifetime.interest.has(peer),'Disconnected traffic interest leaked');
lifetime.tick(6000,[]);check(lifetime.actors.size===0,'Unobserved world population never retired');
const clock=make();clock.tick(1000,[[0,0,13]]);actor=[...clock.actors.values()][0];const before=actor.pose.position.slice();clock.tick(900,[[0,0,13]]);
check(Math.hypot(...actor.pose.position.map((v,i)=>v-before[i]))===0,'Reversed clock replayed motion');
// A long straight approach isolates ordinary following/braking from the
// separate open intersection/retail driving policy. The player is a real
// task obstacle input, not a forced zero-speed or visibility callback.
const largeBytes=square(200),largeGraph=new TrafficRoads(largeBytes,crc32(largeBytes)),observer=[50,20,13];
const stopping=make({graph:largeGraph});stopping.tick(0,[observer]);actor=[...stopping.actors.values()][0];
check(actor.pose.direction[0]>.99&&actor.pose.position[0]<150,'Straight braking fixture did not start before obstacle');
const pedestrian={position:[160,0,13],length:1,width:.7};let peakSpeed=0;
for(let n=1;n<=100;n++){
 stopping.tick(n*100,[observer],[pedestrian]);peakSpeed=Math.max(peakSpeed,actor.state.speed);
 check(actor.pose.position[0]<157.5,'Traffic body crossed a stopped pedestrian');
}
check(peakSpeed>5&&actor.state.speed<.01,'Moving traffic failed to brake for a pedestrian');
const stopped=actor.pose.position.slice();let previousPosition=stopped;
for(let n=201;n<=260;n++){
 stopping.tick(n*50,[observer],[]);
 check(Math.hypot(...actor.pose.position.map((v,i)=>v-previousPosition[i]))<=.401,'Clearing an obstacle teleported its traffic car');
 previousPosition=actor.pose.position.slice();
}
check(actor.pose.position[0]>stopped[0]+10&&actor.state.speed>7,'Cleared road did not resume ordinary acceleration');
const stacked=make({graph:largeGraph});stacked.tick(0,[observer]);const lowerCar=[...stacked.actors.values()][0];
for(let n=1;n<=80;n++)stacked.tick(n*100,[observer],[{...pedestrian,position:[160,0,33]}]);
check(lowerCar.pose.position[0]>160,'Traffic stopped for an obstacle on a different road height');
const crossing=make({graph:largeGraph});crossing.tick(0,[observer]);const crossingCar=[...crossing.actors.values()][0];
const longVehicle={position:[160,4,13],direction:[0,1],length:20,width:2};
for(let n=1;n<=100;n++)crossing.tick(n*100,[observer],[longVehicle]);
check(crossingCar.pose.position[0]<157,'Traffic crossed the actual footprint of a perpendicular long vehicle');
const alongside=make({graph:largeGraph});alongside.tick(0,[observer]);const passingCar=[...alongside.actors.values()][0];
for(let n=1;n<=80;n++)alongside.tick(n*100,[observer],[{...longVehicle,direction:[1,0]}]);
check(passingCar.pose.position[0]>160,'Long vehicle orientation incorrectly blocked a separate parallel lane');
const offset=make({graph:largeGraph});offset.tick(0,[observer]);const offsetCar=[...offset.actors.values()][0];
for(let n=1;n<=100;n++)offset.tick(n*100,[observer],[{position:[160,4,13],direction:[1,0],length:4,width:2,centre:[4,0]}]);
check(offsetCar.pose.position[0]<156,'Model-origin offset displaced a blocking vehicle out of its actual lane');
const occupied=make();occupied.tick(0,[[0,0,13]],[{position:[40,24,13],direction:[0,1],length:4,width:2}]);
check([...occupied.actors.values()].every(a=>Math.hypot(a.pose.position[0]-40,a.pose.position[1]-24)>4),
 'Traffic spawned inside an existing vehicle instead of rejecting the occupied road sample');
const disabledBytes=square(200,13,[32,32,32,32]),disabledGraph=new TrafficRoads(disabledBytes,crc32(disabledBytes));
const disabled=make({graph:disabledGraph});disabled.tick(0,[observer]);
check(disabled.actors.size===0,'Traffic spawned on source-marked closed roads');
const partialBytes=square(200,13,[0,4096,8192|32,12288]),partialGraph=new TrafficRoads(partialBytes,crc32(partialBytes));
const partial=make({graph:partialGraph});partial.tick(0,[observer]);
check(partial.actors.size===1,'One closed road incorrectly disabled the remaining open approach');
for(let n=1;n<=50;n++){
 partial.tick(n*100,[observer]);
 for(const car of partial.actors.values())for(const leg of [car.state.first,car.state.second,car.state.next,...car.state.ahead].filter(Boolean))
  check(!partialGraph.closed(partialGraph.from(leg.link))&&!partialGraph.closed(partialGraph.to(leg.link)),'Connected route entered a closed road');
}
console.log('PASS authoritative traffic tasks '+checks+' checks; invented road/world boundaries, no real-world physics, browser/native App or retail claim');
