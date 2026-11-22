// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const wire=require('./pedestrian_protocol');
const validPoint=p=>Array.isArray(p)&&p.length===3&&p.every(Number.isFinite)&&p.every(v=>Math.abs(v)<10000);
const distance=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]));
const observationRadius=110;
/** Independent server population tasks on verified original pavements. This
 * implements walking, streamed lifetime, obstacle waits, flee goals, injury
 * and death. Original retail density/zone policy, traffic, police, social and
 * combat AI remain separate tasks; this is not a complete original population.
 */
class Pedestrians {
 constructor({graph,models,ground,clear,random=Math.random,maximum=64,perObserver=12}){
  if(!graph||!Array.isArray(models)||!models.length||models.length>312||
    !models.every(id=>Number.isInteger(id)&&id>=0&&id<=311)||typeof ground!=='function'||typeof clear!=='function')throw Error('Population resources');
  this.graph=graph;this.models=Object.freeze([...new Set(models)]);this.ground=ground;this.clear=clear;this.random=random;
  this.maximum=Math.max(0,Math.min(64,maximum|0));this.perObserver=Math.max(0,Math.min(20,perObserver|0));
  this.actors=new Map();this.interest=new Map();this.nextID=1;this.spawnAt=0;this.lastTime=null;
 }
 #choose(rows){return rows[Math.min(rows.length-1,Math.max(0,Math.floor(this.random()*rows.length)))];}
 #route(actor,away=null){
  const here=this.graph.point(actor.node),options=this.graph.neighbors(actor.node).filter(link=>link.id!==actor.previous);
  const links=options.length?options:this.graph.neighbors(actor.node);if(!links.length)return false;
  let selected;
  if(away){selected=links.slice().sort((a,b)=>distance(this.graph.point(b.id),away)-distance(this.graph.point(a.id),away))[0];}
  else{
   const direction=actor.previous===null?null:here.map((v,i)=>v-this.graph.point(actor.previous)[i]);
   const forward=direction?links.filter(link=>{const to=this.graph.point(link.id);return(to[0]-here[0])*direction[0]+(to[1]-here[1])*direction[1]>=-0.1;}):links;
   selected=this.#choose(forward.length?forward:links);
  }
  actor.to=selected.id;actor.crossing=selected.kind;actor.goal=this.graph.point(actor.to).slice(0,2);return true;
 }
 #spawn(observer,now){
  for(let attempt=0;attempt<8;attempt++){
   const angle=this.random()*Math.PI*2,radius=35+this.random()*40;
   const query=[observer[0]+Math.cos(angle)*radius,observer[1]+Math.sin(angle)*radius,observer[2]];
   const nearest=this.graph.nearest(query,18,10000);if(!nearest)continue;
   const point=this.graph.point(nearest.id),height=this.ground(point);
   if(!Number.isFinite(height)||Math.abs(height-point[2])>2||
      [...this.actors.values()].some(actor=>distance(actor.position,point)<5))continue;
   let id=this.nextID;for(let n=0;this.actors.has(id)&&n<65536;n++)id=(id+1)&65535;
   if(this.actors.has(id))return;this.nextID=(id+1)&65535;
   const actor={id,skin:this.#choose(this.models),seed:Math.floor(this.random()*256)&255,flags:0,
    node:nearest.id,to:nearest.id,previous:null,position:[point[0],point[1],height],goal:point.slice(0,2),
    speed:0,desiredSpeed:1.1,health:100,mood:0,faceWire:0,hitCounter:0,hitWeapon:0,hitPiece:0,hitFromWire:0,
    panicUntil:0,deadAt:null,blockedAt:null,lastSeen:now};
   if(!this.#route(actor))continue;this.actors.set(id,actor);return;
  }
 }
 #advance(actor,dt,now){
  if(actor.health<=0){actor.speed=0;actor.desiredSpeed=0;return;}
  if(now>=actor.panicUntil&&actor.flags&4){actor.flags&=~4;actor.mood=0;actor.desiredSpeed=1.1;}
  let remaining=dt,iterations=0;
  // Bounded server substeps avoid frame-dependent acceleration and route
  // overshoot. Simulation never advances a long disconnected wall-time gap.
  while(remaining>1e-8&&iterations++<64){
   const step=Math.min(0.05,remaining);
   const delta=[actor.goal[0]-actor.position[0],actor.goal[1]-actor.position[1]],length=Math.hypot(...delta);
   if(length<1e-8){actor.previous=actor.node;actor.node=actor.to;if(!this.#route(actor,now<actor.panicUntil?actor.threat:null)){actor.speed=0;break;}continue;}
   const accelerating=Math.min(step,Math.abs(actor.desiredSpeed-actor.speed)/4);
   const acceleration=Math.sign(actor.desiredSpeed-actor.speed)*4;
   const afterAcceleration=actor.speed+acceleration*accelerating;
   const acceleratedTravel=(actor.speed+afterAcceleration)*0.5*accelerating;
   const availableTravel=acceleratedTravel+actor.desiredSpeed*(step-accelerating);
   let elapsed=step;
   // Finish an edge at its actual arrival time, carrying the rest of the
   // admitted interval into the next edge. Never discard a whole substep
   // merely because the destination is close.
   if(availableTravel>length){
    if(length<=acceleratedTravel&&Math.abs(acceleration)>0){
     const arrivalSpeed=Math.sqrt(Math.max(0,actor.speed*actor.speed+2*acceleration*length));
     elapsed=2*length/(actor.speed+arrivalSpeed);
    }else if(actor.desiredSpeed>0){elapsed=accelerating+(length-acceleratedTravel)/actor.desiredSpeed;}
   }
   const next=actor.speed+acceleration*Math.min(elapsed,accelerating);
   const travel=Math.min(length,availableTravel);
   const candidate=[actor.position[0]+delta[0]/length*travel,actor.position[1]+delta[1]/length*travel,actor.position[2]];
   const floor=this.ground(candidate);
   if(!Number.isFinite(floor)||Math.abs(floor-actor.position[2])>0.75||!this.clear(actor.position,candidate)){
    actor.speed=0;actor.flags|=2;actor.blockedAt??=now;
    if(now-actor.blockedAt>1500){actor.previous=null;this.#route(actor);actor.blockedAt=now;}break;
   }
   candidate[2]=floor;actor.position=candidate;actor.speed=next;actor.flags&=~2;actor.blockedAt=null;
   actor.faceWire=Math.atan2(delta[1],delta[0]);
   remaining-=elapsed;
  }
 }
 tick(now,observers){
  if(!Number.isFinite(now)||!Array.isArray(observers))throw Error('Population clock/observers');
  observers=observers.filter(validPoint).slice(0,32);
  const dt=this.lastTime===null?0:Math.max(0,Math.min(0.5,(now-this.lastTime)/1000));this.lastTime=now;
  for(const [id,actor]of this.actors){
   // Refresh only lifetimes inside the same distance we publish. An actor
   // held indefinitely in an invisible outer ring can exhaust shared capacity
   // and leave the observer's new area empty. Other observers still retain it.
   if(observers.some(point=>distance(point,actor.position)<observationRadius))actor.lastSeen=now;
   if(now-actor.lastSeen>3000||(actor.deadAt!==null&&now-actor.deadAt>20000)){this.actors.delete(id);continue;}
   this.#advance(actor,dt,now);
  }
  if(now>=this.spawnAt&&observers.length){
   this.spawnAt=now+250;
   for(const observer of observers){
    if(this.actors.size>=this.maximum)break;
    const nearby=[...this.actors.values()].filter(actor=>distance(actor.position,observer)<observationRadius).length;
    if(nearby<this.perObserver)this.#spawn(observer,now);
   }
  }
 }
 packets(owner,position,now){
  const visible=validPoint(position)?[...this.actors.values()].filter(actor=>distance(actor.position,position)<observationRadius):[];
  const ids=new Set(visible.map(actor=>actor.id)),previous=this.interest.get(owner)||new Set();this.interest.set(owner,ids);
  const removed=[...previous].filter(id=>!ids.has(id)),packets=[];
  if(removed.length)packets.push(wire.gone(removed));
  if(visible.length){
   // Prediction consumes speed/wanted independently of the wait flag. Keep
   // the task's desired speed for obstacle recovery, but publish a stopped
   // goal while geometry prevents movement.
   packets.push(wire.free(visible.map(actor=>({...actor,desiredSpeed:actor.flags&2?0:actor.desiredSpeed})),Math.floor(now)),wire.more(visible.map(actor=>({
    ...actor,weapon:0,burning:false,phone:false,crouching:false,cpr:false,foe:0,thrown:0
   }))));
  }
  return packets;
 }
 forget(owner){this.interest.delete(owner);}
 get(target){if(typeof target!=='string'||!/^p(?:0|[1-9]\d{0,4})$/.test(target))return null;return this.actors.get(Number(target.slice(1)))||null;}
 damage(target,amount,{weapon=0,from,now,piece=3}={}){
  const actor=this.get(target);
  if(!actor||actor.health<=0||!Number.isFinite(amount)||amount<=0||amount>1000||!validPoint(from)||!Number.isFinite(now)||
     !Number.isInteger(piece)||piece<3||piece>9)return false;
  actor.health=Math.max(0,actor.health-amount);actor.hitCounter=(actor.hitCounter+1)&31;actor.hitWeapon=weapon;
  actor.hitPiece=piece;actor.hitFromWire=Math.atan2(from[1]-actor.position[1],from[0]-actor.position[0]);
  if(actor.health===0){actor.flags|=9;actor.deadAt=now;actor.speed=0;actor.desiredSpeed=0;actor.goal=actor.position.slice(0,2);}
  else{this.flee(actor,from,now);}
  return true;
 }
 flee(actor,from,now){
  if(!actor||actor.health<=0||!validPoint(from)||!Number.isFinite(now))return;
  actor.flags|=4;actor.mood=0;actor.threat=from.slice();actor.panicUntil=Math.max(actor.panicUntil,now+6000);actor.desiredSpeed=3.2;
  // Choose a real graph edge away from the threat. Do not teleport to a node
  // or let clients supply the destination or health.
  if(distance(actor.position,this.graph.point(actor.node))<0.5)this.#route(actor,from);
 }
 gunshot(origin,now){if(!validPoint(origin)||!Number.isFinite(now))return;for(const actor of this.actors.values())if(distance(actor.position,origin)<35)this.flee(actor,origin,now);}
}
module.exports={Pedestrians,validPoint};
