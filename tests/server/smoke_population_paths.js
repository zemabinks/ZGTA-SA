#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const{PedestrianPaths,PathFormatError,crc32}=require('../../server/population/pedestrian_paths.js');
let checks=0;const check=(value,message)=>{assert(value,message);checks++;};
// Independent two-node golden, with sections at explicit byte boundaries.
function graph(){
 const bytes=Buffer.alloc(72);bytes.writeUInt32LE(0x44504453,0);bytes.writeUInt32LE(1,4);bytes.writeUInt32LE(2,8);bytes.writeUInt32LE(2,12);
 [8,16,24,80,160,240].forEach((v,i)=>bytes.writeInt16LE(v,32+i*2));[0,1,2].forEach((v,i)=>bytes.writeUInt32LE(v,44+i*4));
 bytes[60]=8;bytes[61]=16;bytes.writeUInt16LE(1,64);bytes.writeUInt16LE(0,66);bytes[68]=3;bytes[69]=1;return bytes;
}
const bytes=graph(),original=Buffer.from(bytes),paths=new PedestrianPaths(bytes,crc32(bytes));
check(paths.nodeCount===2&&paths.linkCount===2,'Counts');check(JSON.stringify(paths.point(0))==='[1,2,3]','GTA units/axes');
check(paths.widthRaw(1)===16,'Original width retained without invented scale');
check(paths.neighbors(0)[0].id===1&&paths.neighbors(0)[0].crossesRoad&&paths.neighbors(0)[0].hasPedSignal,'Cross-area compact edge/kind');
check(paths.nearest([1.1,2,3],1).id===0,'Spatial lookup');check(paths.nearest([100,100,100],1)===null,'No invented nearest route');
bytes.fill(0);check(paths.point(0)[0]===1&&paths.neighbors(1)[0].id===0,'Caller mutated admitted graph');
for(const offset of [0,4,8,12,44,48,52,64]){
 const altered=Buffer.from(original);if(offset===64)altered.writeUInt16LE(3,offset);else altered.writeUInt32LE(0xffffffff,offset);
 assert.throws(()=>new PedestrianPaths(altered),PathFormatError);checks++;
}
for(const length of [0,31,32,33,44,45,60,64,68,71]){assert.throws(()=>new PedestrianPaths(original.subarray(0,length)),PathFormatError);checks++;}
assert.throws(()=>new PedestrianPaths(Buffer.concat([original,Buffer.alloc(1)])),PathFormatError);checks++;
assert.throws(()=>new PedestrianPaths(original,'00000000'),PathFormatError);checks++;
assert.throws(()=>paths.point(65535),PathFormatError);checks++;
assert.throws(()=>paths.nearest([0,NaN,0],20),PathFormatError);checks++;
assert.throws(()=>paths.nearest([1e300,0,0],20),PathFormatError);checks++;
assert.throws(()=>paths.nearest([1,2,3],100,1),PathFormatError);checks++;
check(crc32(Buffer.from('123456789'))==='cbf43926','Standard CRC32 golden');
if(process.argv[2]){
 const input=fs.readFileSync(path.resolve(process.argv[2])),actual=new PedestrianPaths(input);
 const closest=actual.nearest([1480,-1738,13],100);check(closest!==null,'Owned exterior graph has no spawn-area query result');
 let edges=0;for(let id=0;id<actual.nodeCount;id++)edges+=actual.neighbors(id).length;
 check(edges===actual.linkCount,'Owned graph omitted adjacency');
 console.log(JSON.stringify({status:'PASS_PRIVATE_GRAPH',nodes:actual.nodeCount,edges,crc32:actual.crc32,sha256:actual.sha256,scope:'Actual converted original graph admission/query only; no spawning/AI/rendered/retail acceptance'}));
}
console.log(JSON.stringify({status:'PASS',checks,scope:'Authored SDPD graph, CRC, malformed data, ownership and bounded queries; actual owner data optional'}));
