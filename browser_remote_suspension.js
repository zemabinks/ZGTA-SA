// SPDX-License-Identifier: AGPL-3.0-only
// Independent wheel-local integration. No original engine implementation/assets.
(function install(root){
 'use strict';
 const finite=v=>Number.isFinite(v),array=v=>v&&finite(v.x)&&finite(v.y)&&finite(v.z);
 function rotate(p,q){
  const x=p.x,y=p.y,z=p.z,u=q.x,v=q.y,w=q.z,r=q.w;
  const tx=2*(v*z-w*y),ty=2*(w*x-u*z),tz=2*(u*y-v*x);
  return{x:x+r*tx+v*tz-w*ty,y:y+r*ty+w*tx-u*tz,z:z+r*tz+u*ty-v*tx};
 }
 function reset(built){
  if(!Array.isArray(built?.wheels))return;
  for(const wheel of built.wheels)if(wheel.mesh?.position&&finite(wheel.home?.z))wheel.mesh.position.z=wheel.home.z;
 }
 function project(built,group,environment){
  if(!built||!['car','trailer'].includes(built.kind)||built.hydraulics||!group||!Array.isArray(built.wheels)||built.wheels.length>16)return false;
  const table=built.table,upper=table?.upper,lower=table?.lower;
  if(!finite(upper)||!finite(lower)||upper<=lower||lower < -5||upper>5||(Number(table.flags)&131072)!==0)return false;
  // Remote groups have no local driver suspension owner. A transient absence
  // of real contacts restores canonical locals, never a stale fabricated floor.
  reset(built);
  const world=environment?.world,R=environment?.RAPIER;
  if(!world||typeof world.castRayAndGetNormal!=='function'||typeof R?.Ray!=='function')return false;
  if(!group.position?.clone||!group.quaternion?.clone||!group.scale?.clone||!group.getWorldPosition||!group.getWorldQuaternion)return false;
  const p=group.getWorldPosition(group.position.clone()),q=group.getWorldQuaternion(group.quaternion.clone());
  if(!array(p)||![q.x,q.y,q.z,q.w].every(finite)||Math.abs(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w-1)>.003)return false;
  const scale=group.getWorldScale?.(group.scale.clone());
  if(!scale||![scale.x,scale.y,scale.z].every(x=>finite(x)&&Math.abs(x-1)<.001))return false;
  const up=rotate({x:0,y:1,z:0},q);if(up.y<=.15)return false;
  const selected=new Map();
  for(const wheel of built.wheels){
   const c=wheel.centre,r=wheel.radius;if(!array(c)||![c.x,c.y,c.z].every(x=>Math.abs(x)<100)||!finite(r)||r<=0||r>5||upper-lower+r>10)return false;
   const index=2*Number(!wheel.left)+Number(!wheel.front),old=selected.get(index);
   if(!old||(wheel.front?c.z<old.centre.z:c.z>old.centre.z))selected.set(index,wheel);
  }
  if(!selected.size)return false;
  const offsets=new Map();
  for(const[index,wheel]of selected){
   const c=wheel.centre,offset=rotate({x:c.x,y:c.y+upper,z:c.z},q),length=upper-lower+wheel.radius;
   const at={x:p.x+offset.x,y:p.y+offset.y,z:p.z+offset.z},way={x:-up.x,y:-up.y,z:-up.z};
   const hit=world.castRayAndGetNormal(new R.Ray(at,way),length,true,undefined,0xffff0001,undefined,undefined,collider=>{
    const body=collider.parent();return !body||body.isFixed();
   });
   // This browser interface has no complete-cell/known-clear capability. A
   // miss is unknown, not proof of airborne travel. Native handles that case
   // with its explicit collision coverage map.
   if(!hit||!finite(hit.timeOfImpact)||hit.timeOfImpact<0||hit.timeOfImpact>length+.00001||!array(hit.normal))return false;
   const normal=hit.normal,dot=normal.x*up.x+normal.y*up.y+normal.z*up.z;
   if(dot<=.05)return false;
   const tyre=built.flat?.[index]??0;if(tyre>=2){offsets.set(index,lower);continue}
   offsets.set(index,Math.max(lower,Math.min(upper,upper+wheel.radius*(tyre===1?.75:1)-hit.timeOfImpact)));
  }
  for(const wheel of built.wheels){const index=2*Number(!wheel.left)+Number(!wheel.front);if(wheel.mesh?.position&&finite(wheel.home?.z)&&offsets.has(index))wheel.mesh.position.z=wheel.home.z+offsets.get(index)}
  return true;
 }
 function apply(built,group,environment){try{return project(built,group,environment)}catch{reset(built);return false}}
 const api=Object.freeze({identity:'zgta-remote-suspension-v1',apply});
 if(typeof module==='object'&&module.exports)module.exports=api;
 else root.ZGTARemoteSuspension=api;
})(typeof globalThis==='object'?globalThis:this);
