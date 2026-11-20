// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const crypto=require('node:crypto');
class PathFormatError extends Error {}
const requireValue=(value,message)=>{if(!value)throw new PathFormatError(message);};
function crc32(bytes){
 let result=0xffffffff;
 for(const byte of bytes){result^=byte;for(let bit=0;bit<8;bit++)result=(result>>>1)^((result&1)?0xedb88320:0);}
 return((result^0xffffffff)>>>0).toString(16).padStart(8,'0');
}
/** Immutable original-pedestrian graph, not population, steering or original AI.
 * All coordinates remain GTA Z-up feet. Raw node bytes have no assigned use.
 */
class PedestrianPaths {
 #xyz;#offsets;#targets;#kinds;#width;#cells=new Map();
 constructor(input,expectedCRC=null){
  requireValue(Buffer.isBuffer(input)&&input.length>=32&&input.length<=3*1024*1024,'SDPD byte budget');
  const bytes=Buffer.from(input);
  requireValue(bytes.readUInt32LE(0)===0x44504453&&bytes.readUInt32LE(4)===1,'SDPD profile');
  const nodes=bytes.readUInt32LE(8),links=bytes.readUInt32LE(12);
  requireValue(nodes>0&&nodes<=65535&&links<=300000,'SDPD record budget');
  let cursor=32;
  const section=(count,size)=>{const start=cursor;cursor+=count*size;requireValue(cursor<=bytes.length,'SDPD section range');cursor=(cursor+3)&~3;requireValue(cursor<=bytes.length,'SDPD padding range');return start;};
  const xyz=section(nodes*3,2),offsets=section(nodes+1,4);section(nodes,1);
  const widths=section(nodes,1),targets=section(links,2),kinds=section(links,1);
  requireValue(cursor===bytes.length,'SDPD trailing or missing bytes');
  const actualCRC=crc32(bytes);
  if(expectedCRC!==null)requireValue(typeof expectedCRC==='string'&&/^[0-9a-f]{8}$/.test(expectedCRC)&&actualCRC===expectedCRC,'SDPD source CRC');
  this.nodeCount=nodes;this.linkCount=links;this.bytes=bytes.length;this.crc32=actualCRC;
  this.sha256=crypto.createHash('sha256').update(bytes).digest('hex');
  this.#xyz=new Float64Array(nodes*3);this.#offsets=new Uint32Array(nodes+1);
  this.#targets=new Uint16Array(links);this.#kinds=new Uint8Array(links);this.#width=new Uint8Array(nodes);
  for(let i=0;i<=nodes;i++){
   const value=bytes.readUInt32LE(offsets+i*4);
   requireValue(value<=links&&(i===0?value===0:value>=this.#offsets[i-1]),'SDPD nonmonotonic adjacency');
   if(i>0)requireValue(value-this.#offsets[i-1]<=15,'Original pedestrian degree budget');
   this.#offsets[i]=value;
  }
  requireValue(this.#offsets[nodes]===links,'SDPD terminal adjacency');
  for(let i=0;i<links;i++){
   this.#targets[i]=bytes.readUInt16LE(targets+i*2);this.#kinds[i]=bytes[kinds+i];
   requireValue(this.#targets[i]<nodes,'SDPD unresolved node reference');
  }
  for(let id=0;id<nodes;id++){
   for(let axis=0;axis<3;axis++)this.#xyz[id*3+axis]=bytes.readInt16LE(xyz+(id*3+axis)*2)/8;
   this.#width[id]=bytes[widths+id];
   const key=this.#cell(this.#xyz[id*3],this.#xyz[id*3+1]);
   if(!this.#cells.has(key))this.#cells.set(key,[]);
   this.#cells.get(key).push(id);
  }
  Object.freeze(this);
 }
 #cell(x,y){return Math.floor(x/64)+':'+Math.floor(y/64);}
 #check(id){requireValue(Number.isInteger(id)&&id>=0&&id<this.nodeCount,'SDPD node identity');}
 point(id){this.#check(id);return Object.freeze([this.#xyz[id*3],this.#xyz[id*3+1],this.#xyz[id*3+2]]);}
 widthRaw(id){this.#check(id);return this.#width[id];}
 neighbors(id){
  this.#check(id);const result=[];
  for(let i=this.#offsets[id];i<this.#offsets[id+1];i++)result.push(Object.freeze({id:this.#targets[i],kind:this.#kinds[i],crossesRoad:(this.#kinds[i]&1)!==0,hasPedSignal:(this.#kinds[i]&2)!==0}));
  return Object.freeze(result);
 }
 nearest(point,radius,maximumScannedNodes=100000){
  requireValue(Array.isArray(point)&&point.length===3&&point.every(Number.isFinite)&&Number.isFinite(radius)&&radius>0&&radius<=500,'SDPD nearest query');
  requireValue(Math.abs(point[0])<=1000000&&Math.abs(point[1])<=1000000,'SDPD coordinate budget');
  requireValue(Number.isInteger(maximumScannedNodes)&&maximumScannedNodes>0&&maximumScannedNodes<=100000,'SDPD scan budget');
  let result=null,best=radius*radius,scanned=0;
  for(let x=Math.floor((point[0]-radius)/64);x<=Math.floor((point[0]+radius)/64);x++)for(let y=Math.floor((point[1]-radius)/64);y<=Math.floor((point[1]+radius)/64);y++){
   for(const id of this.#cells.get(x+':'+y)||[]){
    requireValue(++scanned<=maximumScannedNodes,'SDPD scan budget exceeded');
    const at=id*3,distance=(this.#xyz[at]-point[0])**2+(this.#xyz[at+1]-point[1])**2+(this.#xyz[at+2]-point[2])**2;
    if(distance<best||(distance===best&&(result===null||id<result.id))){best=distance;result={id,distance:Math.sqrt(distance)};}
   }
  }
  return result?Object.freeze(result):null;
 }
}
module.exports={PedestrianPaths,PathFormatError,crc32};
