// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Independent self-host placement protocol. These are server admission rules,
// not a reconstruction of Rockstar's save/checkpoint or anti-cheat systems.
const DEFAULT_SPOT=Object.freeze([1480,-1738,13,0]);
const SOURCES=new Set(['spawn','respawn','home.enter','home.exit','home.visit','pilot','passenger']);
const key=v=>typeof v==='string'&&v.length>0&&v.length<=128;
const spot=v=>Array.isArray(v)&&v.length===4&&v.every(Number.isFinite)&&
  v.every(n=>Math.abs(n)<=1_000_000);
function record(value,kind){
  if(!value||typeof value!=='object'||Array.isArray(value)||!spot(value.spot)||
     !(value.home===null||key(value.home))||
     !(value.context===null||key(value.context))||
     !Number.isSafeInteger(value.updatedAt)||value.updatedAt<0||
     (kind==='foot'?value.source!=='foot':!SOURCES.has(value.source)))return null;
  return{spot:[...value.spot],home:value.home,source:value.source,
    context:value.context,updatedAt:value.updatedAt};
}
function normalize(value){
  if(!value||typeof value!=='object'||Array.isArray(value)||value.version!==1)
    return{version:1,foot:null,intent:null};
  return{version:1,foot:record(value.foot,'foot'),intent:record(value.intent,'intent')};
}
function create({isCurrent,validFoot,validTarget,now=()=>Date.now()}={}){
  if(typeof isCurrent!=='function'||typeof validFoot!=='function'||typeof validTarget!=='function')
    throw new Error('Placement validation callbacks are required.');
  const current=peer=>!!(peer?.positionAckEnabled&&peer.inventoryAckEnabled&&peer.healthAckEnabled&&
    typeof peer.inventoryConnection==='string'&&isCurrent(peer));
  const admits=(player,value,intent)=>{
    try{return !!value&&(intent?validTarget(player,value):validFoot(player,value));}
    catch{return false;}
  };
  function saved(player){
    const value=normalize(player.reconnectPlacement);player.reconnectPlacement=value;return value;
  }
  function select(player){
    const value=saved(player);
    if(admits(player,value.intent,true))return value.intent;
    if(admits(player,value.foot,false))return value.foot;
    return{spot:[...DEFAULT_SPOT],home:null,source:'spawn',context:null,updatedAt:now()};
  }
  function begin(peer){
    if(!current(peer))return null;
    if(peer.placementSession?.connection===peer.inventoryConnection)return hello(peer);
    const target=select(peer.player);
    peer.placementSession={connection:peer.inventoryConnection,revision:0,target,
      hello:{spot:[...target.spot],home:target.home,
        placement:{connection:peer.inventoryConnection,revision:0}}};
    peer.player.insideHome=target.home;
    return hello(peer);
  }
  function envelope(peer){
    const value=peer?.placementSession;
    if(!current(peer)||value?.connection!==peer.inventoryConnection)return null;
    return{connection:value.connection,revision:value.revision};
  }
  function hello(peer){
    const value=peer?.placementSession?.hello;
    return envelope(peer)&&value?{spot:[...value.spot],home:value.home,
      placement:{...value.placement}}:null;
  }
  function matches(peer,value){
    const expected=envelope(peer);
    return !!expected&&value!==null&&typeof value==='object'&&!Array.isArray(value)&&
      value.connection===expected.connection&&Number.isSafeInteger(value.revision)&&
      value.revision>=0&&value.revision===expected.revision;
  }
  function issue(peer,packet,{source,home=null,context=null}={}){
    const value=peer?.placementSession,expected=envelope(peer);
    const target=record({spot:[packet.x,packet.y,packet.z,packet.h*Math.PI/180],
      home,source,context,updatedAt:now()},'intent');
    if(!expected||!target||value.revision===Number.MAX_SAFE_INTEGER)
      throw new Error('Invalid or exhausted placement session. Reconnect before teleporting.');
    // Persistent intent is committed before the wire command. A queued old
    // position can never replace it just because the client has not read it.
    const store=saved(peer.player);store.intent=target;
    value.revision++;value.target=target;
    return{...packet,placement:envelope(peer)};
  }
  function canIssue(peer){
    return !!envelope(peer)&&peer.placementSession.revision<Number.MAX_SAFE_INTEGER;
  }
  function observe(peer,state){
    if(!matches(peer,state?.placement)||peer.player.health<=0||state.walking!==true||
       state.driving===true||state.passenger===true||state.riding||state.on||
       state.air===true||state.crouch===true||(state.act??0)!==0||
       ![state.x,state.y,state.z,state.heading].every(Number.isFinite))return false;
    const target=record({spot:[state.x,state.y,state.z,state.heading],
      home:peer.player.insideHome||null,source:'foot',context:null,updatedAt:now()},'foot');
    if(!admits(peer.player,target,false))return false;
    const store=saved(peer.player);
    if(!store.intent&&store.foot?.home===target.home&&
       store.foot.spot.every((n,i)=>Object.is(n,target.spot[i])))return false;
    store.foot=target;store.intent=null;
    peer.placementSession.target=target;
    return true;
  }
  return{begin,hello,envelope,matches,issue,canIssue,observe,select,snapshot:saved};
}
module.exports={DEFAULT_SPOT,normalize,create};
