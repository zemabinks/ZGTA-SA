// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Existing browser protocol38 pedestrian channel. Actors are server entities,
// never account/Peer rows. These codecs do not grant damage or spawn authority.
class PedestrianProtocolError extends Error {}
const requireValue=(value,message)=>{if(!value)throw new PedestrianProtocolError(message);};
const integer=(value,min,max,label)=>{requireValue(Number.isSafeInteger(value)&&value>=min&&value<=max,label);return value;};
function quantize(value,scale,min,max,label){
 requireValue(Number.isFinite(value),label);
 return integer(Math.round(value*scale),min,max,label);
}
function angle(value){
 requireValue(Number.isFinite(value),'NPC wire angle');
 return Math.round((((value%(2*Math.PI))+2*Math.PI)%(2*Math.PI))*128/Math.PI)&255;
}
function frame(tag,payload){
 integer(tag,0,255,'NPC record tag');requireValue(Buffer.isBuffer(payload)&&payload.length<=32767,'NPC record length');
 const prefix=payload.length<128?Buffer.from([tag,payload.length]):Buffer.from([tag,0x80|(payload.length&127),payload.length>>7]);
 return Buffer.concat([prefix,payload]);
}
function batch(rows,maximum){
 requireValue(Array.isArray(rows)&&rows.length<=maximum,'NPC record count');const ids=new Set();
 for(const row of rows){integer(row.id,0,65535,'NPC identity');requireValue(!ids.has(row.id),'Duplicate NPC identity');ids.add(row.id);}
}
function free(rows,epochMilliseconds){
 batch(rows,1024);integer(epochMilliseconds,0,Number.MAX_SAFE_INTEGER,'NPC epoch clock');
 const payload=Buffer.alloc(4+rows.length*21);payload.writeUInt32BE(epochMilliseconds>>>0,0);
 rows.forEach((row,index)=>{
  const at=4+index*21;integer(row.skin,0,4095,'NPC skin');integer(row.flags,0,15,'NPC flags');integer(row.seed,0,255,'NPC appearance seed');
  requireValue(Array.isArray(row.position)&&row.position.length===3&&Array.isArray(row.goal)&&row.goal.length===2,'NPC free goal shape');
  payload.writeUInt16BE(row.id,at);payload.writeUInt16BE(row.skin|(row.flags<<12),at+2);payload[at+4]=row.seed;
  payload.writeInt32BE(quantize(row.position[0],1000,-2147483648,2147483647,'NPC x'),at+5);
  payload.writeInt32BE(quantize(row.position[1],1000,-2147483648,2147483647,'NPC y'),at+9);
  payload.writeInt16BE(quantize(row.position[2],8,-32768,32767,'NPC feet z'),at+13);
  payload.writeInt16BE(quantize(row.goal[0]-row.position[0],16,-32768,32767,'NPC goal x'),at+15);
  payload.writeInt16BE(quantize(row.goal[1]-row.position[1],16,-32768,32767,'NPC goal y'),at+17);
  payload[at+19]=quantize(row.speed,32,0,255,'NPC speed');payload[at+20]=quantize(row.desiredSpeed,32,0,255,'NPC desired speed');
 });
 return frame(10,payload);
}
function gone(ids){
 requireValue(Array.isArray(ids)&&ids.length<=4096,'NPC removal count');const seen=new Set(),payload=Buffer.alloc(ids.length*2);
 ids.forEach((id,index)=>{integer(id,0,65535,'NPC removal identity');requireValue(!seen.has(id),'Duplicate NPC removal');seen.add(id);payload.writeUInt16BE(id,index*2);});
 return frame(8,payload);
}
function more(rows){
 batch(rows,1024);const payload=Buffer.alloc(rows.length*11);
 rows.forEach((row,index)=>{
  const at=index*11;integer(row.mood,0,15,'NPC mood');integer(row.weapon,0,46,'NPC weapon');integer(row.hitWeapon,0,255,'NPC hit weapon');
  integer(row.hitCounter,0,31,'NPC hit counter');integer(row.hitPiece,0,9,'NPC hit piece');integer(row.foe,0,65535,'NPC wire foe');
  requireValue(row.hitPiece===0||row.hitPiece>=3,'Unrepresentable NPC hit piece');
  for(const key of ['burning','phone','crouching','cpr'])requireValue(typeof row[key]==='boolean','NPC state flag');
  const piece=row.hitPiece>=3?row.hitPiece-2:0;
  payload.writeUInt16BE(row.id,at);payload[at+2]=row.mood|(row.burning?16:0)|(row.phone?32:0)|(row.crouching?64:0)|(row.cpr?128:0);
  payload[at+3]=row.weapon;payload[at+4]=row.hitWeapon;payload[at+5]=angle(row.hitFromWire);
  payload[at+6]=row.hitCounter|(piece<<5);payload[at+7]=angle(row.faceWire);
  payload.writeUInt16BE(row.foe,at+8);payload[at+10]=quantize(row.thrown,4,0,255,'NPC thrown state');
 });
 return frame(11,payload);
}
module.exports={PedestrianProtocolError,frame,free,gone,more};
