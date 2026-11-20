#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const assert=require('node:assert/strict');
const{PedestrianProtocolError,frame,free,gone,more}=require('../../server/population/pedestrian_protocol.js');
let checks=0;
const actor={id:258,skin:7,flags:5,seed:42,position:[1.25,-2.5,3.125],goal:[1.75,-1.5],speed:1.5,desiredSpeed:2};
assert.equal(free([actor],0x12345678).toString('hex'),'0a1912345678010250072a000004e2fffff63c0019000800103040');checks++;
assert.equal(gone([258,1]).toString('hex'),'080401020001');checks++;
const state={id:258,mood:3,burning:true,phone:false,crouching:true,cpr:false,weapon:22,hitWeapon:24,hitFromWire:Math.PI/2,hitCounter:3,hitPiece:3,faceWire:Math.PI,foe:65535,thrown:1.25};
assert.equal(more([state]).toString('hex'),'0b0b0102531618402380ffff05');checks++;
assert.equal(frame(10,Buffer.alloc(127)).subarray(0,2).toString('hex'),'0a7f');checks++;
assert.equal(frame(10,Buffer.alloc(128)).subarray(0,3).toString('hex'),'0a8001');checks++;
assert.equal(frame(10,Buffer.alloc(32767)).subarray(0,3).toString('hex'),'0affff');checks++;
assert.throws(()=>frame(10,Buffer.alloc(32768)),PedestrianProtocolError);checks++;
assert.equal(free([actor],0x112345678).subarray(2,6).toString('hex'),'12345678');checks++;
for(const changes of [{id:-1},{id:65536},{skin:4096},{flags:16},{seed:256},{position:[NaN,0,0]},{position:[1,2,10000]},{goal:[10000,0]},{speed:8},{desiredSpeed:-1}]){
 assert.throws(()=>free([{...actor,...changes}],1),PedestrianProtocolError);checks++;
}
assert.throws(()=>free([actor,actor],1),PedestrianProtocolError);checks++;
assert.throws(()=>gone([1,1]),PedestrianProtocolError);checks++;
assert.throws(()=>more([{...state,burning:1}]),PedestrianProtocolError);checks++;
assert.throws(()=>more([{...state,hitCounter:32}]),PedestrianProtocolError);checks++;
assert.throws(()=>more([{...state,hitPiece:2}]),PedestrianProtocolError);checks++;
assert.throws(()=>more([{...state,faceWire:Infinity}]),PedestrianProtocolError);checks++;
console.log(JSON.stringify({status:'PASS',checks,scope:'Authored exact big-endian actor records, length and epoch-wrap goldens; no server, client simulation, damage, socket, renderer or original runtime acceptance'}));
