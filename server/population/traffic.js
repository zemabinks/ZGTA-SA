// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const motion=require('./traffic_motion'),wire=require('./traffic_protocol');
const finitePoint=p=>Array.isArray(p)&&p.length===3&&p.every(Number.isFinite)&&p.every(v=>Math.abs(v)<=1e6);
const separation=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1],a[2]-b[2]);
const cloneState=s=>({...s,first:{...s.first},second:{...s.second},next:s.next?{...s.next}:null,ahead:s.ahead.map(l=>({...l}))});
const observationRadius=125;
function dimensions(value){
 const centre=value.centre??[0,0];
 if(!Number.isInteger(value.id)||value.id<400||value.id>611||![value.length,value.width].every(n=>Number.isFinite(n)&&n>=.05&&n<=200)||
    !Array.isArray(centre)||centre.length!==2||!centre.every(n=>Number.isFinite(n)&&Math.abs(n)<=200))throw Error('Traffic vehicle bounds');
 return Object.freeze({id:value.id,length:value.length,width:value.width,centre:Object.freeze(centre.slice())});
}
function footprint(value,reference){
 const position=value.pose?.position||value.position,raw=value.pose?.direction||value.direction||reference,size=Math.hypot(...raw);
 const direction=size>1e-8?raw.map(n=>n/size):reference,model=value.model&&typeof value.model==='object'?value.model:value,centre=model.centre??[0,0];
 return {position:[position[0]+direction[1]*centre[0]+direction[0]*centre[1],position[1]-direction[0]*centre[0]+direction[1]*centre[1],position[2]],
  direction,length:model.length??1,width:model.width??1};
}
function overlaps(a,b){
 if(Math.abs(a.position[2]-b.position[2])>3)return false;
 const dx=b.position[0]-a.position[0],dy=b.position[1]-a.position[1];
 // Separating axes of both oriented rectangles. This is spawn admission,
 // not dynamic contact resolution or a replacement for vehicle physics.
 for(const axis of [a.direction,[a.direction[1],-a.direction[0]],b.direction,[b.direction[1],-b.direction[0]]]){
  const extent=body=>Math.abs(axis[0]*body.direction[0]+axis[1]*body.direction[1])*body.length/2+
   Math.abs(axis[0]*body.direction[1]-axis[1]*body.direction[0])*body.width/2;
  if(Math.abs(dx*axis[0]+dy*axis[1])>extent(a)+extent(b)+.5)return false;
 }
 return true;
}

/** Independent server-owned road population, not retail CCarCtrl/vehicle AI.
 * One fixed clock owns all observers' cars. Clients consume ordinary compact
 * records, then an atomic registered-car handoff for interactive ownership.
 * Signals, original zone selection, police and dynamic collision physics are
 * separate requirements; none is inferred from graph or file availability.
 */
class Traffic {
 #dimensions=new Map();
 constructor({graph,models,ground,clear,maximum=32,perObserver=6,random=Math.random,reserved=()=>new Set(),speeds=[8,12,18,10],vehicleDimensions=[]}){
  if(!graph||!Array.isArray(models)||!models.length||models.length>212||typeof ground!=='function'||typeof clear!=='function'||typeof random!=='function'||typeof reserved!=='function'||
   !Number.isInteger(maximum)||maximum<0||maximum>64||!Number.isInteger(perObserver)||perObserver<0||perObserver>16||
   !Array.isArray(speeds)||speeds.length!==4||!speeds.every(s=>Number.isFinite(s)&&s>=1&&s<=40))throw Error('Traffic configuration');
  if(!Array.isArray(vehicleDimensions)||vehicleDimensions.length>212)throw Error('Traffic vehicle bounds budget');
  for(const value of vehicleDimensions){const shape=dimensions(value);if(this.#dimensions.has(shape.id))throw Error('Duplicate traffic vehicle bounds');this.#dimensions.set(shape.id,shape);}
  const seen=new Set();
  this.models=models.map(m=>{
   if(!Number.isInteger(m.id)||m.id<400||m.id>611||seen.has(m.id)||!Number.isFinite(m.length)||m.length<1||m.length>25||
    !Number.isFinite(m.width)||m.width<0.5||m.width>5||!Array.isArray(m.colors)||!m.colors.length||m.colors.length>32||
    !m.colors.every(c=>Array.isArray(c)&&c.length===2&&c.every(n=>Number.isInteger(n)&&n>=0&&n<=255)))throw Error('Traffic model dimensions/identity');
   const shape=dimensions(m),known=this.#dimensions.get(m.id);
   if(known&&(Math.abs(known.length-shape.length)>1e-6||Math.abs(known.width-shape.width)>1e-6||known.centre.some((v,i)=>Math.abs(v-shape.centre[i])>1e-6)))throw Error('Selected traffic model bounds differ from source');
   this.#dimensions.set(m.id,shape);seen.add(m.id);return Object.freeze({...m,centre:shape.centre,colors:Object.freeze(m.colors.map(c=>Object.freeze(c.slice())))});
  });
  Object.assign(this,{graph,ground,clear,maximum,perObserver,random,reserved,speeds:speeds.slice()});
  this.actors=new Map();this.interest=new Map();this.nextID=0;this.serial=0;this.previousTime=null;this.remainder=0;this.faults=0;this.lastFault=null;
 }
 dimensionsFor(id){return this.#dimensions.get(id)||null;}
 #allowed(link){return this.graph.laneCount(link)>0&&[this.graph.from(link),this.graph.to(link)].every(id=>!this.graph.water(id)&&!this.graph.closed(id));}
 #random(){const value=this.random();if(!Number.isFinite(value)||value<0||value>=1)throw Error('Traffic random source');return value;}
 #choose(previous){
  let links=this.graph.links(this.graph.to(previous.link)).filter(link=>this.#allowed(link)&&this.graph.to(link)!==this.graph.from(previous.link));
  // A dead end stops rather than silently sending a car against a one-way
  // lane or inventing an off-road U-turn.
  if(!links.length)return null;
  const link=links[Math.floor(this.#random()*links.length)],count=this.graph.laneCount(link);
  return {link,lane:Math.min(previous.lane,count-1)};
 }
 #refill(state){
  let tail=state.ahead.at(-1)||state.next;
  while(tail&&state.ahead.length<6){const next=this.#choose(tail);if(!next)break;state.ahead.push(next);tail=next;}
 }
 #identity(){
  const reserved=this.reserved();
  for(let attempt=0;attempt<65535;attempt++){
   const id=this.nextID;this.nextID=(this.nextID+1)%65535;
   if(!this.actors.has(id)&&!reserved.has(id))return id;
  }return null;
 }
 #spawn(observer,now,obstacles){
  const candidates=this.graph.near(observer,110,1024).filter(r=>r.distance>=30&&this.#allowed(r.link));
  if(!candidates.length)return false;
  // A bounded scan makes one failed/blocked district cheap. The graph itself
  // supplies permitted road direction and original lane geometry.
  const offset=Math.floor(this.#random()*candidates.length);
  for(let n=0;n<Math.min(24,candidates.length);n++){
   const link=candidates[(offset+n)%candidates.length].link,count=this.graph.laneCount(link);if(!count)continue;
   const first={link,lane:Math.floor(this.#random()*count)},second=this.#choose(first);if(!second)continue;
   const model=this.models[Math.floor(this.#random()*this.models.length)],next=this.#choose(second);
   const state={first,second,next,ahead:[],progress:this.#random(),speed:0,wanted:0,rate:4,side:0,aim:0,flags:0};this.#refill(state);
   if(motion.span(state,this.graph)<1)continue;
   const pose=motion.position(state,this.graph),height=this.ground(pose.position);
   if(!Number.isFinite(height)||Math.abs(height-pose.position[2])>4)continue;pose.position[2]=height;
   if(separation(pose.position,observer)<30||separation(pose.position,observer)>110||
    [...this.actors.values()].some(a=>separation(a.pose.position,pose.position)<(a.model.length+model.length)/2+6))continue;
   const body=footprint({pose,model},pose.direction);
   if(obstacles.some(o=>overlaps(body,footprint(o,pose.direction))))continue;
   if(!this.#clearSpawn(body))continue;
   const id=this.#identity();if(id===null)return false;
   const colors=model.colors[Math.floor(this.#random()*model.colors.length)].slice();
   this.actors.set(id,{id,generation:++this.serial,model,colors,state,pose,health:1000,flags:0,crew:1,deadSeats:0,lastObserved:now,blockedSince:null});return true;
  }return false;
 }
 #clearSpawn(body){
  // Check the occupied body before publishing its first lifetime. A future
  // movement ray cannot reject a car which already appeared inside a wall.
  // Sample support at each endpoint so sloped roads are not flattened.
  // Three rays are a bounded static admission test, not volumetric collision.
  const d=body.direction,side=[d[1]*body.width*.4,-d[0]*body.width*.4];
  return [0,-1,1].every(offset=>{
   const ends=[-1,1].map(sign=>body.position.map((v,i)=>i<2?v+d[i]*body.length/2*sign+side[i]*offset:v));
   for(const point of ends){
    const height=this.ground(point);
    if(!Number.isFinite(height)||Math.abs(height-body.position[2])>4)return false;
    point[2]=height+.8;
   }
   return this.clear(ends[0],ends[1]);
  });
 }
 #target(actor,others,obstacles){
  const body=footprint(actor,actor.pose.direction),p=body.position,d=body.direction;
  let wanted=this.speeds[this.graph.speedClass(this.graph.to(actor.state.first.link))],gap=Infinity;
  for(const obstacle of others.concat(obstacles)){
   if(obstacle===actor||!finitePoint(obstacle.pose?.position||obstacle.position))continue;
   const other=footprint(obstacle,d),q=other.position,dx=q[0]-p[0],dy=q[1]-p[1];
   if(Math.abs(q[2]-p[2])>3)continue;
   const ahead=dx*d[0]+dy*d[1],side=Math.abs(dx*d[1]-dy*d[0]);
   const parallel=Math.abs(d[0]*other.direction[0]+d[1]*other.direction[1]),cross=Math.abs(d[0]*other.direction[1]-d[1]*other.direction[0]);
   const along=parallel*other.length/2+cross*other.width/2,across=cross*other.length/2+parallel*other.width/2;
   if(ahead<=0||side>body.width/2+across+0.6)continue;
   const distance=ahead-body.length/2-along-2;
   gap=Math.min(gap,distance);
  }
  if(Number.isFinite(gap))wanted=Math.min(wanted,Math.sqrt(Math.max(0,2*6*gap)));
  return Math.max(0,wanted);
 }
 #clearMotion(actor,pose){
  const side=[actor.pose.direction[1]*actor.model.width*0.4,-actor.pose.direction[0]*actor.model.width*0.4];
  return [0,-1,1].every(offset=>this.clear(actor.pose.position.map((v,i)=>v+(i<2?side[i]*offset:0.8)),pose.position.map((v,i)=>v+(i<2?side[i]*offset:0.8))));
 }
 #step(now,obstacles){
  const actors=[...this.actors.values()];
  // Plan from one shared snapshot; iteration order must not let a trailing
  // car see another car's future position in the same simulation tick.
  const targets=new Map(actors.map(a=>[a.id,this.#target(a,actors,obstacles)]));
  for(const actor of actors){
   const state=actor.state,previous=cloneState(state);state.wanted=targets.get(actor.id);state.rate=state.wanted<state.speed?6:4;
   try{
    motion.advance(state,0.05,this.graph,previous=>state.ahead.shift()||this.#choose(previous));this.#refill(state);
    const pose=motion.position(state,this.graph),height=this.ground(pose.position);
    let clear=Number.isFinite(height)&&Math.abs(height-pose.position[2])<=4;
    if(clear){
     pose.position[2]=height;
     // Original world visibility is a static-geometry admission boundary,
     // not a replacement for dynamic Rapier collision or crash simulation.
     clear=this.#clearMotion(actor,pose);
    }
    if(!clear){actor.state=previous;actor.state.speed=0;actor.state.wanted=0;actor.state.rate=6;actor.blockedSince??=now;}
    else{actor.pose=pose;actor.blockedSince=state.speed<0.1&&state.wanted===0?(actor.blockedSince??now):null;}
   }catch(error){
    // Bad/degenerate paths quarantine this lifetime; they cannot take down
    // every player's server clock or emit nonfinite records.
    this.faults++;this.lastFault=String(error.message).slice(0,240);this.actors.delete(actor.id);
   }
  }
 }
 tick(now,observers,obstacles=[]){
  if(!Number.isSafeInteger(now)||now<0||!Array.isArray(observers)||observers.length>256||!Array.isArray(obstacles)||obstacles.length>4096)throw Error('Traffic clock/observer budget');
  observers=observers.filter(finitePoint);obstacles=obstacles.filter(o=>finitePoint(o.position)&&
   [o.length??1,o.width??1].every(n=>Number.isFinite(n)&&n>0&&n<=200)&&
   (o.centre===undefined||(Array.isArray(o.centre)&&o.centre.length===2&&o.centre.every(Number.isFinite)))&&
   (o.direction===undefined||(Array.isArray(o.direction)&&o.direction.length===2&&o.direction.every(Number.isFinite))));
  // A wall-clock adjustment cannot rewind a shared physical sample or erase
  // its unconsumed fraction. The rebound would otherwise integrate it again.
  now=Math.max(now,this.previousTime??now);
  if(this.previousTime!==null)this.remainder+=Math.min(0.5,(now-this.previousTime)/1000);this.previousTime=now;
  while(this.remainder+1e-10>=0.05){this.remainder=Math.max(0,this.remainder-0.05);this.#step(now-this.remainder*1000,obstacles);}
  for(const actor of this.actors.values()){
   // Only observable lifetimes refresh retention. Keeping a stopped car in
   // a larger invisible ring forever can exhaust the shared spawn budget.
   if(observers.some(p=>separation(p,actor.pose.position)<observationRadius))actor.lastObserved=now;
   if(now-actor.lastObserved>5000)this.actors.delete(actor.id);
  }
  for(const observer of observers){
   let count=[...this.actors.values()].filter(a=>separation(a.pose.position,observer)<110).length;
   for(let attempts=0;count<this.perObserver&&this.actors.size<this.maximum&&attempts<8;attempts++)if(this.#spawn(observer,now,obstacles))count++;
  }
 }
 packets(peer,position,now){
  if(!Number.isSafeInteger(now)||now<0)throw Error('Traffic publication clock');
  const previous=this.interest.get(peer)||new Set(),actors=finitePoint(position)?[...this.actors.values()].filter(a=>separation(a.pose.position,position)<observationRadius):[];
  const selected=new Set(actors.map(a=>a.id)),gone=[...previous].filter(id=>!selected.has(id)),packets=[];
  if(gone.length)packets.push(wire.gone(gone));
  if(actors.length){
   const rows=actors.map(a=>({...a.state,id:a.id,model:a.model.id,colors:a.colors,health:a.health,flags:a.flags,crew:a.crew,deadSeats:a.deadSeats}));
   // An event-only publication does not advance simulation. Preserve the
   // actual sample clock so receivers extrapolate the elapsed interval once.
   packets.push(Buffer.concat([wire.base(rows,this.sampleTime??now),wire.more(rows),wire.crew(rows),wire.ahead(rows)]));
  }
  if(selected.size)this.interest.set(peer,selected);else this.interest.delete(peer);return packets;
 }
 get sampleTime(){return this.previousTime===null?null:Math.round(this.previousTime-this.remainder*1000);}
 poseAt(actor,now){
  const at=this.sampleTime;
  if(at===null||!Number.isSafeInteger(now)||now<at||now-at>500||this.actors.get(actor.id)!==actor)return null;
  const state=cloneState(actor.state);
  try{
   motion.advance(state,(now-at)/1000,this.graph,()=>state.ahead.shift()||null);
   const pose=motion.position(state,this.graph),height=this.ground(pose.position);
   if(!Number.isFinite(height)||Math.abs(height-pose.position[2])>4)return null;pose.position[2]=height;
   if(!this.#clearMotion(actor,pose))return null;
   return {...pose,speed:state.speed};
  }catch{return null;}
 }
 promotable(peer,id,position,now=this.previousTime){
  if(!Number.isInteger(id)||!finitePoint(position)||!this.interest.get(peer)?.has(id))return null;
  const actor=this.actors.get(id),pose=actor&&this.poseAt(actor,now);
  // Registered parked rows have no autonomous velocity owner. Until a full
  // moving-car jacking handoff exists, never discard a moving driver's
  // momentum merely because someone requested its door.
  return pose&&pose.speed<=0.5&&separation(pose.position,position)<=8?actor:null;
 }
 retire(id,generation){const actor=this.actors.get(id);if(!actor||actor.generation!==generation)return false;this.actors.delete(id);return true;}
 forget(peer){this.interest.delete(peer);}
}
module.exports={Traffic};
