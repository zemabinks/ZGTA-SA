// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Geometry-compatible traffic motion. This matches our native channel's curve
// and distance parameter, not the retail executable's full vehicle physics.
const add=(a,b)=>[a[0]+b[0],a[1]+b[1]],sub=(a,b)=>[a[0]-b[0],a[1]-b[1]],mul=(a,t)=>[a[0]*t,a[1]*t];
const dot=(a,b)=>a[0]*b[0]+a[1]*b[1],cross=(a,b)=>a[0]*b[1]-a[1]*b[0],distance=(a,b)=>Math.hypot(...sub(a,b));
function intersection(p,u,q,v){const denominator=cross(u,v);return denominator===0?-1:-cross(sub(p,q),v)/denominator;}
function factor(p,u,q,v){const value=dot(u,v);if(value<=0)return 1/3;if(value>0.7){const d=distance(p,q);return d===0?0:Math.abs(cross(sub(p,q),v))/d/3;}return(1-value/0.7)/3;}
function length(p,u,q,v){const a=intersection(p,u,q,v),b=intersection(q,mul(v,-1),p,u);return a>0&&b>0?a+b:distance(p,q)/(1-factor(p,u,q,v));}
function curve(p,u,q,v,t){
 const first=intersection(p,u,q,v),second=intersection(q,mul(v,-1),p,u);
 if(first>0&&second>0){
  const corner=Math.min(5,first,second),entry=first-corner,exit=second-corner,total=entry+2*corner+exit,at=t*total;
  if(at<entry)return add(p,mul(u,at));if(at>entry+2*corner)return add(q,mul(v,at-total));
  const share=(at-entry)/(2*corner),a=add(p,mul(u,entry+corner*share)),b=sub(q,mul(v,exit+corner*(1-share)));
  return add(a,mul(sub(b,a),share));
 }
 const d=distance(p,q),f=factor(p,u,q,v),total=d/(1-f),at=t*total,blend=total<1e-5?0.5:0.5-0.5*Math.cos(Math.PI*at/total);
 const travel=total<1e-5?0:total/(2*Math.PI)*Math.sin(2*Math.PI*at/total)*f+(1-f)*at,a=add(p,mul(u,travel)),b=add(q,mul(v,travel-d));
 return add(a,mul(sub(b,a),blend));
}
function endpoints(state,graph){const a=graph.lanePoint(state.first.link,state.first.lane),b=graph.lanePoint(state.second.link,state.second.lane);return[a.position,a.direction,b.position,b.direction];}
function span(state,graph){return length(...endpoints(state,graph));}
function position(state,graph){
 const args=endpoints(state,graph),t=Math.min(1,Math.max(0,state.progress)),p=curve(...args,t);
 let direction=sub(curve(...args,Math.min(1,state.progress+0.01)),curve(...args,Math.max(0,state.progress-0.01))),size=Math.hypot(...direction);
 if(size<1e-6){direction=add(args[1],mul(sub(args[3],args[1]),state.progress));size=Math.hypot(...direction);}
 direction=size===0?[1,0]:mul(direction,1/size);
 const side=state.side||0,padding=[direction[1]*side,-direction[0]*side];
 return {position:[p[0]+padding[0],p[1]+padding[1],graph.height(state.first.link,state.second.link,t)],direction,heading:Math.atan2(direction[0],direction[1])};
}
/** Consume physical distance through the connected route. No per-edge elapsed
 * time is discarded, and exhaustion cannot extrapolate past the final edge.
 */
function advance(state,seconds,graph,choose){
 if(!Number.isFinite(seconds)||seconds<0||seconds>0.5||![state.progress,state.speed,state.wanted,state.rate].every(Number.isFinite))throw Error('Traffic motion budget/state');
 if(seconds===0)return;
 const rate=Math.max(0.05,state.rate),reach=Math.abs(state.wanted-state.speed)/rate;
 const next=seconds<reach?state.speed+Math.sign(state.wanted-state.speed)*rate*seconds:state.wanted;
 const travel=seconds<reach?(state.speed+next)*seconds/2:(state.speed+state.wanted)*reach/2+state.wanted*(seconds-reach);
 state.speed=next;let remaining=travel,transitions=0;
 while(remaining>0){
  const size=Math.max(0.01,span(state,graph)),available=(1-state.progress)*size;
  if(remaining<available){state.progress+=remaining/size;break;}
  remaining-=Math.max(0,available);state.progress=1;
  if(!state.next){state.speed=0;state.wanted=0;break;}
  if(++transitions>256)throw Error('Traffic route transition budget');
  state.first=state.second;state.second=state.next;state.next=choose(state.second);state.progress=0;
 }
}
module.exports={intersection,factor,length,curve,span,position,advance};
