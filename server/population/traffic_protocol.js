// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const {frame}=require('./pedestrian_protocol');
const integer=(v,low,high)=>{if(!Number.isSafeInteger(v)||v<low||v>high)throw Error('Traffic wire integer');return v;};
const quantize=(v,scale,high)=>{if(!Number.isFinite(v))throw Error('Traffic wire scalar');return integer(Math.round(v*scale),0,high);};
function batch(rows,max=1024){
 if(!Array.isArray(rows)||rows.length>max)throw Error('Traffic wire count');const seen=new Set();
 for(const row of rows){integer(row.id,0,65535);if(seen.has(row.id))throw Error('Duplicate traffic identity');seen.add(row.id);}
}
function base(rows,now){
 batch(rows);integer(now,0,Number.MAX_SAFE_INTEGER);const payload=Buffer.alloc(4+rows.length*19);payload.writeUInt32BE(now>>>0);
 rows.forEach((r,i)=>{const at=4+i*19;
  payload.writeUInt16BE(r.id,at);payload.writeUInt16BE(integer(r.model,400,611),at+2);
  payload[at+4]=integer(r.colors[0],0,255);payload[at+5]=integer(r.colors[1],0,255);
  payload.writeUInt16BE(integer(r.first.link,0,65534),at+6);payload.writeUInt16BE(integer(r.second.link,0,65534),at+8);
  payload.writeUInt16BE(r.next?integer(r.next.link,0,65534):65535,at+10);
  payload.writeUInt16BE(integer(r.first.lane,0,15)|(integer(r.second.lane,0,15)<<4)|((r.next?integer(r.next.lane,0,15):0)<<8),at+12);
  payload.writeUInt16BE(quantize(r.progress,65535,65535),at+14);payload[at+16]=quantize(r.speed,4,255);payload[at+17]=quantize(r.wanted,4,255);payload[at+18]=quantize(r.rate,16,255);
 });return frame(4,payload);
}
function gone(ids){batch(ids.map(id=>({id})),4096);const payload=Buffer.alloc(ids.length*2);ids.forEach((id,i)=>payload.writeUInt16BE(id,i*2));return frame(5,payload);}
function more(rows){batch(rows);const payload=Buffer.alloc(rows.length*6);rows.forEach((r,i)=>{const at=i*6;payload.writeUInt16BE(r.id,at);payload[at+4]=quantize(r.health,1/4,255);payload[at+5]=integer(r.flags||0,0,255);});return frame(9,payload);}
function crew(rows){batch(rows);const payload=Buffer.alloc(rows.length*4);rows.forEach((r,i)=>{payload.writeUInt16BE(r.id,i*4);payload[i*4+2]=integer(r.crew??1,0,3);payload[i*4+3]=integer(r.deadSeats||0,0,7);});return frame(33,payload);}
function ahead(rows){
 batch(rows);const payloads=rows.map(r=>{
  if(!Array.isArray(r.ahead)||r.ahead.length>8)throw Error('Traffic route window');
  const payload=Buffer.alloc(3+r.ahead.length*3);payload.writeUInt16BE(r.id);payload[2]=r.ahead.length;
  r.ahead.forEach((leg,i)=>{payload.writeUInt16BE(integer(leg.link,0,65534),3+i*3);payload[5+i*3]=integer(leg.lane,0,15);});return payload;
 });return frame(34,Buffer.concat(payloads));
}
module.exports={base,gone,more,crew,ahead};
