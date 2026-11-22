// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const crypto=require('node:crypto');
const {crc32}=require('./pedestrian_paths');
class RoadFormatError extends Error {}
const requireValue=(value,message)=>{if(!value)throw new RoadFormatError(message);};

/** Validated SDRDv1 road queries shared with the native traffic channel.
 * Original graph bytes stay owner-local. Route selection and driving policy
 * belong to the authoritative simulation, not this geometry reader.
 */
class TrafficRoads {
 #points;#offsets;#flags;#from;#to;#nav;#navigation;#cells=new Map();
 constructor(input,expectedCRC){
  requireValue(Buffer.isBuffer(input)&&input.length>=32&&input.length<=8*1048576,'SDRD byte budget');
  const bytes=Buffer.from(input);
  requireValue(bytes.readUInt32LE(0)===0x44524453&&bytes.readUInt32LE(4)===1,'SDRD profile');
  const nodes=bytes.readUInt32LE(8),links=bytes.readUInt32LE(12),navis=bytes.readUInt32LE(16);
  requireValue([nodes,links,navis].every(n=>n>0&&n<=65535),'SDRD record budget');
  let cursor=32;
  const section=(count,size)=>{const at=cursor;cursor+=count*size;requireValue(cursor<=bytes.length,'SDRD section range');cursor=(cursor+3)&~3;requireValue(cursor<=bytes.length,'SDRD padding');return at;};
  const xyz=section(nodes*3,2),offset=section(nodes+1,4),flags=section(nodes,4);
  section(nodes,1);
  const target=section(links,4),navi=section(links,4),xy=section(navis*2,2),attached=section(navis,4),direction=section(navis*2,1),lanes=section(navis,4);
  requireValue(cursor===bytes.length,'SDRD exact end');
  const actualCRC=crc32(bytes);
  requireValue(typeof expectedCRC==='string'&&/^[0-9a-f]{8}$/.test(expectedCRC)&&actualCRC===expectedCRC,'SDRD source CRC');
  this.nodeCount=nodes;this.linkCount=links;this.naviCount=navis;this.crc32=actualCRC;
  this.sha256=crypto.createHash('sha256').update(bytes).digest('hex');this.bytes=bytes.length;
  this.#offsets=new Uint32Array(nodes+1);this.#flags=new Uint32Array(nodes);
  this.#points=[];this.#from=new Uint16Array(links);this.#to=new Uint16Array(links);this.#nav=new Uint16Array(links);this.#navigation=[];
  for(let i=0;i<=nodes;i++){
   const value=bytes.readUInt32LE(offset+i*4);
   requireValue(value<=links&&(i===0?value===0:value>=this.#offsets[i-1]),'SDRD adjacency');this.#offsets[i]=value;
  }
  requireValue(this.#offsets[nodes]===links,'SDRD terminal adjacency');
  for(let i=0;i<nodes;i++){
   this.#points.push(Object.freeze([0,1,2].map(axis=>bytes.readInt16LE(xyz+i*6+axis*2)/8)));this.#flags[i]=bytes.readUInt32LE(flags+i*4);
   for(let link=this.#offsets[i];link<this.#offsets[i+1];link++)this.#from[link]=i;
  }
  for(let i=0;i<links;i++){
   const to=bytes.readUInt32LE(target+i*4),nav=bytes.readUInt32LE(navi+i*4);
   requireValue(to<nodes&&nav<navis,'SDRD unresolved link');this.#to[i]=to;this.#nav[i]=nav;
  }
  for(let i=0;i<navis;i++){
   const node=bytes.readUInt32LE(attached+i*4);requireValue(node<nodes,'SDRD unresolved navigation');
   this.#navigation.push(Object.freeze({node,position:Object.freeze([bytes.readInt16LE(xy+i*4)/8,bytes.readInt16LE(xy+i*4+2)/8]),
    direction:Object.freeze([bytes.readInt8(direction+i*2)/100,bytes.readInt8(direction+i*2+1)/100]),flags:bytes.readUInt32LE(lanes+i*4)}));
  }
  for(let link=0;link<links;link++){
   if(!this.laneCount(link)||this.water(this.#from[link])||this.water(this.#to[link]))continue;
   const point=this.lanePoint(link,0).position,key=this.#cell(...point);
   if(!this.#cells.has(key))this.#cells.set(key,[]);this.#cells.get(key).push(link);
  }
  Object.freeze(this);
 }
 #cell(x,y){return Math.floor(x/64)+':'+Math.floor(y/64);}
 #node(id){requireValue(Number.isInteger(id)&&id>=0&&id<this.nodeCount,'SDRD node identity');}
 #link(id){requireValue(Number.isInteger(id)&&id>=0&&id<this.linkCount,'SDRD link identity');}
 point(id){this.#node(id);return this.#points[id];}
 from(id){this.#link(id);return this.#from[id];}
 to(id){this.#link(id);return this.#to[id];}
 // Retained channel query name. These original bits distinguish highway
 // categories; the server's speed table is independent admission policy.
 speedClass(id){this.#node(id);return this.#flags[id]>>>12&3;}
 closed(id){this.#node(id);return (this.#flags[id]&32)!==0;}
 water(id){this.#node(id);return (this.#flags[id]&128)!==0;}
 links(id){this.#node(id);return Array.from({length:this.#offsets[id+1]-this.#offsets[id]},(_,i)=>this.#offsets[id]+i);}
 laneCount(link){this.#link(link);const nav=this.#navigation[this.#nav[link]];return nav.flags>>>(nav.node===this.#to[link]?8:11)&7;}
 lanePoint(link,lane){
  this.#link(link);requireValue(Number.isInteger(lane)&&lane>=0&&lane<=15,'SDRD lane identity');
  const nav=this.#navigation[this.#nav[link]],forward=nav.node===this.#to[link],a=nav.flags>>>8&7,b=nav.flags>>>11&7;
  const base=a===0?0.5-b/2:b===0?0.5-a/2:0.5+(nav.flags&255)/16/5.4;
  const offset=(lane+base)*5.4,direction=nav.direction.map(v=>v*(forward?1:-1));
  return {position:[nav.position[0]+direction[1]*offset,nav.position[1]-direction[0]*offset],direction};
 }
 height(first,second,progress){
  this.#link(first);this.#link(second);requireValue(Number.isFinite(progress)&&progress>=0&&progress<=1,'SDRD progress');
  const center=this.#points[this.#to[first]][2];
  return progress<0.5?(this.#points[this.#from[first]][2]+center)/2+(center-this.#points[this.#from[first]][2])*progress:
   center+(this.#points[this.#to[second]][2]-center)*(progress-0.5);
 }
 near(point,radius=100,limit=512){
  requireValue(Array.isArray(point)&&point.length===3&&point.every(Number.isFinite)&&point.every(v=>Math.abs(v)<=1e6)&&
   Number.isFinite(radius)&&radius>0&&radius<=250&&Number.isInteger(limit)&&limit>0&&limit<=4096,'SDRD nearest budget');
  const result=[];let scanned=0;
  for(let x=Math.floor((point[0]-radius)/64);x<=Math.floor((point[0]+radius)/64);x++)for(let y=Math.floor((point[1]-radius)/64);y<=Math.floor((point[1]+radius)/64);y++){
   for(const link of this.#cells.get(x+':'+y)||[]){
    requireValue(++scanned<=65535,'SDRD scan budget');const p=this.lanePoint(link,0).position,z=(this.point(this.from(link))[2]+this.point(this.to(link))[2])/2;
    const distance=Math.hypot(p[0]-point[0],p[1]-point[1],z-point[2]);if(distance<=radius)result.push({link,distance});
   }
  }
  return result.sort((a,b)=>a.distance-b.distance||a.link-b.link).slice(0,limit);
 }
}
module.exports={TrafficRoads,RoadFormatError};
