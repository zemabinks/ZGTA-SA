// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const assert=require('node:assert/strict');
const {square}=require('./traffic_fixture'),{crc32}=require('../../server/population/pedestrian_paths');
const {TrafficRoads}=require('../../server/population/traffic_roads'),motion=require('../../server/population/traffic_motion'),wire=require('../../server/population/traffic_protocol');
let checks=0;const check=(value,message)=>{assert(value,message);checks++;};
const input=square(),graph=new TrafficRoads(input,crc32(input));
check(graph.nodeCount===4&&graph.linkCount===4&&graph.naviCount===4,'Invented graph counts');
for(let id=0;id<4;id++){
 check(graph.from(id)===id&&graph.to(id)===(id+1)%4,'Directed link identity');
 check(graph.links(id).length===1&&graph.links(id)[0]===id,'Adjacency identity');
 check(graph.laneCount(id)===1&&graph.speedClass(id)===id&&!graph.water(id),'Lane/speed/water fields');
 check(Math.abs(Math.hypot(...graph.lanePoint(id,0).direction)-1)<1e-12,'Direction quantization');
 for(const progress of [0,.25,.5,.75,1])check(graph.height(id,(id+1)%4,progress)===13,'Flat height profile');
}
check(graph.near([40,20,13],1)[0].link===1,'Spatial query selects actual road');
const closedBytes=square(40,13,[0,32,0,0]),closedGraph=new TrafficRoads(closedBytes,crc32(closedBytes));
check(closedGraph.closed(1)&&!closedGraph.closed(0),'Original closure flag was confused with road class');
input.fill(0);check(graph.point(1)[0]===40,'Caller mutation changed admitted graph');
for(const make of [()=>new TrafficRoads(square(),'00000000'),()=>new TrafficRoads(square(),null),()=>new TrafficRoads(Buffer.alloc(0),'00000000'),
 ()=>{const p=square();p.writeUInt32LE(65536,8);return new TrafficRoads(p,crc32(p));},
 ()=>{const p=square();p.writeUInt32LE(8,60);return new TrafficRoads(p,crc32(p));},
 ()=>{const p=Buffer.concat([square(),Buffer.alloc(4)]);return new TrafficRoads(p,crc32(p));}]){
 assert.throws(make);checks++;
}
for(const query of [()=>graph.point(4),()=>graph.from(-1),()=>graph.lanePoint(0,-1),()=>graph.height(0,1,NaN),()=>graph.near([0,0,NaN]),()=>graph.near([0,0,0],1e9)]){assert.throws(query);checks++;}
// Known straight geometry, then independently known quadratic corner points.
check(motion.length([0,0],[1,0],[20,0],[1,0])===20,'Straight span');
check(Math.hypot(...motion.curve([0,0],[1,0],[20,0],[1,0],.25).map((v,i)=>v-[5,0][i]))<1e-12,'Straight quarter point');
check(motion.length([0,0],[1,0],[20,20],[0,1])===40,'Corner travel parameter');
check(Math.hypot(...motion.curve([0,0],[1,0],[20,20],[0,1],.5).map((v,i)=>v-[18.75,1.25][i]))<1e-12,'Rounded corner midpoint');
for(const rate of [0.05,4,6])for(const initial of [0,1,10])for(const wanted of [0,2,15]){
 const create=()=>({first:{link:0,lane:0},second:{link:1,lane:0},next:{link:2,lane:0},ahead:[],progress:.99,speed:initial,wanted,rate,side:0});
 const whole=create(),split=create(),choose=previous=>({link:(previous.link+1)%4,lane:0});
 motion.advance(whole,.5,graph,choose);for(let n=0;n<10;n++)motion.advance(split,.05,graph,choose);
 check(Math.abs(whole.progress-split.progress)<1e-12&&whole.first.link===split.first.link,'Route boundary discarded elapsed distance');
 check(Math.abs(whole.speed-split.speed)<1e-12,'Cadence changed acceleration/braking');
 check(motion.position(whole,graph).position.every(Number.isFinite),'Motion emitted invalid position');
}
const row={id:17,model:410,colors:[2,3],first:{link:0,lane:1},second:{link:1,lane:2},next:{link:2,lane:3},ahead:[{link:3,lane:4}],progress:.5,speed:10,wanted:12,rate:4,health:1000,flags:32,crew:2,deadSeats:1};
function payload(packet,tag){check(packet[0]===tag,'Wrong compact tag');const wide=packet[1]&128,at=wide?3:2,length=wide?(packet[1]&127)|(packet[2]<<7):packet[1];check(packet.length===at+length,'Wrong compact frame length');return packet.subarray(at);}
const base=payload(wire.base([row],4294967301),4);
check(base.readUInt32BE(0)===5&&base.readUInt16BE(4)===17&&base.readUInt16BE(6)===410,'Base clock/identity fields');
check(base[8]===2&&base[9]===3&&base.readUInt16BE(16)===0x321,'Base colors/lane fields');
check(base.readUInt16BE(18)===32768&&base[20]===40&&base[21]===48&&base[22]===64,'Base motion scales');
check(payload(wire.more([row]),9)[4]===250,'Vehicle health quantization');
check(payload(wire.crew([row]),33)[2]===2,'Crew metadata');
check(payload(wire.ahead([row]),34).readUInt16BE(3)===3,'Route continuation');
check(payload(wire.gone([17]),5).readUInt16BE(0)===17,'Lifetime removal');
for(const bad of [{...row,id:-1},{...row,progress:NaN},{...row,first:{link:65535,lane:0}},{...row,speed:100},{...row,rate:16}]){assert.throws(()=>wire.base([bad],1));checks++;}
assert.throws(()=>wire.base([row,row],1));checks++;
console.log('PASS traffic geometry/motion/wire '+checks+' checks; invented graph/scalars, no original resources, App or retail claim');
