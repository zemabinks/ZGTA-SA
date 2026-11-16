#!/usr/bin/env node
'use strict';
// Controlled scene/query fixtures execute the unchanged archived coordinator.
// This is state-machine evidence, not a retail or physical-world playtest.
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {createLibrary}=require('./prepare_native_vehicle_rigs');
const lib=createLibrary(),T=lib.T,source=lib.load.factories[58683].toString();
let ledger=[];
const plain=v=>[v.x,v.y,v.z],quat=q=>[q.x,q.y,q.z,q.w];
const record=(body,origin,distance,hit)=>ledger.push({kind:'tread',body:body.handle,origin:plain(origin),distance,result:hit});
const instrumented=source.replace('function _(e,t,l){','function _(e,t,l){let result=_original(e,t,l);_record(e,t,l,result);return result}function _original(e,t,l){');
assert.notEqual(instrumented,source);
const box={exports:{}};
Function('_record','return ('+instrumented+')')(record)(box,box.exports,lib.load);
const scenarios=[];
function scenario(name,rate,configure){
 const coordinator=box.exports.MC(),head=new T.Pq0(0,1.92,0),actor={grounded:true,rising:0};
 let bodies=new Map(),entries=[],tick,log,fit=true;
 actor.fits=(feet,_margin,body)=>{const result=fit;ledger.push({kind:'fits',origin:plain(feet),body:body.handle,result});return result;};
 actor.stand=()=>{actor.grounded=true;actor.rising=0;log.stands++;};
 const scene={RAPIER:{Ball:class{constructor(radius){this.radius=radius;}}},others:new Set(),
  world:{getRigidBody:id=>bodies.get(id),castRay:(ray,distance,_solid,_flags,groups)=>{
   const ordinal=ledger.filter(v=>v.kind==='ray').length;
   let id=tick.broad===false?null:(tick.broadBody??1);
   if(tick.onlyOffset!=null&&ordinal!==tick.onlyOffset)id=null;
   const body=bodies.get(id),height=tick.surface??.2,hit=body&&ray.origin.y>=height&&ray.origin.y-height<=distance;
   const result=hit?{body:id,distance:ray.origin.y-height}:null;
   ledger.push({kind:'ray',origin:plain(ray.origin),distance,groups,result});
   return result?{collider:{parent:()=>body},timeOfImpact:result.distance}:null;
  },intersectionsWithShape:(at,_rotation,shape,callback)=>{
   const selected=[];
   for(const id of tick.near??[1]){const body=bodies.get(id);if(!body)continue;selected.push(id);if(callback({handle:id,parent:()=>body})===false)break;}
   ledger.push({kind:'near',origin:plain(at),radius:shape.radius,limit:4,result:selected});
  }},below:(origin,distance)=>{const result=tick.static===false?null:.35;ledger.push({kind:'below',origin:plain(origin),distance,result});return result;}};
 const input=configure(rate),frames=[];
 for(let index=0;index<input.length;index++){
  tick=input[index];ledger=[];log={stands:0};
  if(tick.drop)coordinator.drop();
  if(tick.head)head.set(...tick.head);
  actor.grounded=tick.grounded??true;actor.rising=tick.rising??0;fit=tick.fits??true;
  const rows=tick.bodies??[{id:1,position:[0,0,0]}];bodies=new Map();scene.others=new Set();
  for(const row of rows){
   const position=new T.Pq0(...row.position),q=new T.PTz().setFromEuler(new T.O9p(...(row.euler??[0,0,0]),'YXZ'));
   q.set(...quat(q).map(Math.fround));
   const velocity=new T.Pq0(...(row.velocity??[0,0,0])),spin=new T.Pq0(...(row.spin??[0,0,0]));
   const body={handle:row.id,isValid:()=>true,isDynamic:()=>row.dynamic??false,translation:()=>position,rotation:()=>q,linvel:()=>velocity,angvel:()=>spin,
    userData:{tread:row.tread===false?null:{positions:new Float32Array([-20,row.treadHeight??.2,-20,20,row.treadHeight??.2,-20,0,row.treadHeight??.2,20]),indices:[0,1,2]}}};
   bodies.set(row.id,body);scene.others.add(row.id);
   row.rotation=quat(q);
  }
  // Stable entry references are deliberate: carry retains them through a
  // later body replacement and presentation reads after the solver step.
  const entryRows=tick.entries??rows.map(row=>({id:'v'+row.id,vehicle:'vehicle'+row.id,handle:row.id,position:row.position,rotation:row.rotation}));
  const previous=entries;entries=entryRows.map(row=>{
   const entry=previous.find(v=>v.id===row.id)??{id:row.id,position:new T.Pq0(),quaternion:new T.PTz()};
   Object.assign(entry,{handle:row.handle,vehicle:row.vehicle??null,driver:row.driver??null,origin:row.origin??0,standing:row.standing??false,built:{kind:row.kind??'car'}});
   entry.position.set(...row.position);const rotation=row.rotation??(bodies.has(row.handle)?quat(bodies.get(row.handle).rotation()):[0,0,0,1]);entry.quaternion.set(...rotation);
   entry.velocity=row.velocity?new T.Pq0(...row.velocity):null;entry.spin=row.spin?new T.Pq0(...row.spin):null;return entry;
  });
  const entryInputs=entries.map(v=>({id:v.id,handle:v.handle,vehicle:v.vehicle,driver:v.driver,origin:v.origin,standing:v.standing,kind:v.built.kind,position:plain(v.position),rotation:quat(v.quaternion),velocity:v.velocity?plain(v.velocity):null,spin:v.spin?plain(v.spin):null}));
  const pre={head:plain(head),grounded:actor.grounded,rising:actor.rising};
  const result=coordinator.carry(scene,actor,head,1.7,1/rate,entries);
  const carry={head:plain(head),move:plain(result.move),yaw:result.yaw,thrown:result.thrown?plain(result.thrown):null};
  head.add(new T.Pq0(...(tick.motor??[0,0,0]))).add(result.move);
  actor.grounded=tick.afterGrounded??actor.grounded;actor.rising=tick.afterRising??actor.rising;
  const motor={head:plain(head),grounded:actor.grounded,rising:actor.rising};
  coordinator.settle(scene,actor,head,1.7,1/rate,tick.jumping??false,tick.moving??true);
  if(tick.presentation)for(const entry of entries)entry.position.add(new T.Pq0(...tick.presentation));
  const drawn=coordinator.drawnAt(new T.Pq0());
  frames.push({tick,pre,rows,entries:entryInputs,
   carry,motor,queries:ledger,expected:{head:plain(head),grounded:actor.grounded,rising:actor.rising,stands:log.stands,through:coordinator.through,riding:coordinator.riding,held:coordinator.held,afloat:coordinator.afloat,on:coordinator.on,drawn:drawn?plain(drawn):null}});
 }
 scenarios.push({name,rate,frames});
}
const sequence=(count,make)=>Array.from({length:count},(_,i)=>make(i));
for(const rate of [20,30,50,60,90,120]){
 scenario('dynamic-turn',rate,r=>sequence(100,i=>({bodies:[{id:1,position:[i/r*.7,Math.sin(i/r)*.08,0],euler:[0,i/r*.3,0],dynamic:true,velocity:[.7,0,0],spin:[0,.3,0]}],presentation:[.001,0,.002]})));
 scenario('kinematic-velocity',rate,r=>sequence(100,i=>({bodies:[{id:1,position:[i/r,0,0]}],entries:[{id:'platform',handle:1,vehicle:'p',position:[i/r,0,0],velocity:[1,0,0],spin:[0,.2,0],standing:true,origin:.13}]})));
 scenario('mesh-fallback',rate,r=>sequence(40,i=>({broad:false,bodies:[{id:1,position:[i/r*.3,0,0]}]})));
 scenario('offset-ground',rate,r=>sequence(30,i=>({onlyOffset:1,bodies:[{id:1,position:[i/r*.2,0,0]}],surface:.15})));
 scenario('slip-and-static',rate,r=>sequence(130,i=>({broad:i<8,bodies:i<8?[{id:1,position:[Math.max(0,i-4)*.4,0,0],dynamic:true,velocity:[i>4?50:0,0,0]}]:[],near:[],static:i>12})));
 scenario('held-roll-replace',rate,r=>sequence(100,i=>{
  const id=i<20?1:2,pos=[i/r*2,0,0],driver=i<35?'driverA':null;
  return {moving:i<70,broad:i<70,bodies:[{id,position:pos,euler:[0,i/r*.2,i>45?1.3:0],dynamic:true,velocity:[8,0,0]}],broadBody:id,
   entries:[{id:'live',vehicle:'v',handle:id,position:pos,driver,kind:'boat'}],near:[id]};
 }));
 scenario('blocked-and-missing',rate,r=>sequence(40,i=>({fits:i!==6,bodies:i===20?[]:[{id:1,position:[i/r*.2,0,0]}],near:i===20?[]:[1]})));
 scenario('jump-release',rate,r=>sequence(80,i=>({jumping:i===6,grounded:i<7||i>35,afterGrounded:i<7||i>35,rising:i<20?3:-3,afterRising:i<20?3:-3,
  broad:i<7||i>35,bodies:[{id:1,position:[i/r,0,0],dynamic:true,velocity:[1,0,0]}],motor:i>=7&&i<35?[0,i<20?.03:-.03,0]:[0,0,0]})));
 scenario('fall-catch',rate,r=>sequence(8,i=>({drop:i===0,head:i===0?[0,2.4,0]:undefined,grounded:false,rising:-4,afterGrounded:false,afterRising:-4,broad:false,motor:[0,-.2,0]})));
 scenario('upside-down-drop',rate,r=>sequence(18,i=>({bodies:[{id:1,position:[0,0,0],euler:[0,0,i>=5?Math.PI:0]}]})));
}
const path=require('node:path'),chunks=path.join(__dirname,'local-only/site/_next/static/chunks');
const footSource=fs.readdirSync(chunks).filter(v=>v.endsWith('.js')).map(v=>fs.readFileSync(path.join(chunks,v),'utf8')).find(v=>v.includes('let tv=Math.min(1,tm?'));
assert(footSource,'Archived pedestrian controller missing');
const awStart=footSource.indexOf('function aw('),awEnd=footSource.indexOf('let ay=',awStart);
const amStart=footSource.indexOf('let am='),amEnd=footSource.indexOf(';function ag(',amStart);
const epStart=footSource.indexOf('ep&&(t$.addScaledVector'),epEnd=footSource.indexOf(',tY.copy',epStart);
assert(awStart>=0&&awEnd>awStart&&amStart>=0&&amEnd>amStart&&epStart>=0&&epEnd>epStart,'Archived knock clauses changed');
const directions=Function('d',footSource.slice(amStart,amEnd)+';'+footSource.slice(awStart,awEnd)+';return {aw,af,am};')(T);
const momentum=Function('T','let ep=null;return {seed(v){ep=new T.Pq0(...v).setY(0)},step(e){let t$=new T.Pq0;'+footSource.slice(epStart,epEnd)+';return [t$.x,t$.y,t$.z]}};')(T);
const knockSides=[],momentumFrames=[];
for(const heading of [-4,-Math.PI,-1,0,1,Math.PI,4])for(let index=0;index<=128;index++){
 const angle=index*Math.PI/64,velocity=[Math.sin(angle)*10,3,Math.cos(angle)*10];
 knockSides.push({heading,velocity,side:directions.aw(new T.Pq0(-velocity[0],-velocity[1],-velocity[2]),new T.Pq0(),-heading),angle:directions.af(directions.am(-velocity[0],-velocity[2])+heading)});
}
for(const rate of [20,30,50,60,90,120]){
 momentum.seed([8,2,-3]);const frames=[];for(let index=0;index<rate*6;index++)frames.push(momentum.step(1/rate));
 momentumFrames.push({rate,velocity:[8,2,-3],frames});
}
fs.writeFileSync(process.argv[2],JSON.stringify({sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),footSourceSHA256:crypto.createHash('sha256').update(footSource).digest('hex'),scenarios,knockSides,momentumFrames}),{mode:0o600});
console.log('Recorded',scenarios.length,'controlled archived support scenarios,',scenarios.reduce((n,s)=>n+s.frames.length,0),'ticks');
