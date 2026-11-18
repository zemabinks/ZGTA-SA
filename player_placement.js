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
// Browser recovery is a distinct, explicitly negotiated admission policy.
const browserSources=new Set(['spawn','respawn','home.enter','home.exit','home.visit','pilot','passenger']);
const browserEnvelope=v=>v&&typeof v==='object'&&!Array.isArray(v)&&typeof v.connection==='string'&&
  /^[A-Za-z0-9_-]{24}$/.test(v.connection)&&Number.isSafeInteger(v.revision)&&v.revision>=0;
function createBrowser({isCurrent,select,validFoot,now=()=>Date.now(),nonce=()=>require('node:crypto').randomBytes(18).toString('base64url')}={}){
  const current=peer=>!!(peer?.browserRecoveryEnabled&&isCurrent(peer)&&peer.browserPlacement);
  const state=peer=>current(peer)?peer.browserPlacement:null;
  function view(peer){const s=state(peer);return s?{connection:s.connection,revision:s.revision}:null;}
  function begin(peer){
    if(peer.browserPlacement)return view(peer);
    const target=select(peer.player),connection=nonce();
    if(!browserEnvelope({connection,revision:0}))throw Error('Invalid browser placement namespace.');
    peer.browserPlacement={connection,revision:0,target,applied:false};
    peer.player.insideHome=target.home;return view(peer);
  }
  function matches(peer,value){const expected=view(peer);return !!expected&&browserEnvelope(value)&&
    value.connection===expected.connection&&value.revision===expected.revision;}
  function packet(peer){const s=state(peer);if(!s||peer.player.health<=0)return null;
    return{t:'tp',x:s.target.spot[0],y:s.target.spot[1],z:s.target.spot[2],
      h:s.target.spot[3]*180/Math.PI,g:1,browserPlacement:view(peer)};}
  function issue(peer,wire,{source,home=null,context=null}={}){
    const s=state(peer);
    if(!s||s.revision===Number.MAX_SAFE_INTEGER||!browserSources.has(source)||
      ![wire.x,wire.y,wire.z,wire.h].every(Number.isFinite))throw Error('Invalid browser placement.');
    const intent={spot:[wire.x,wire.y,wire.z,wire.h*Math.PI/180],home,context,source,updatedAt:now()};
    const saved=normalize({version:1,intent});
    if(!saved.intent)throw Error('Invalid browser placement target.');
    peer.player.reconnectPlacement=normalize(peer.player.reconnectPlacement);
    peer.player.reconnectPlacement.intent=saved.intent;
    s.target=saved.intent;s.revision++;s.applied=false;
    return{...wire,browserPlacement:view(peer)};
  }
  function foot(peer,report){
    if(!matches(peer,report?.browserPlacement)||peer.player.health<=0||report.walking!==true||
      report.driving===true||report.passenger===true||report.riding||report.on||report.vehicle||
      !Number.isFinite(report.health)||report.health<=0||report.air===true||
      ![report.x,report.y,report.z,report.heading].every(Number.isFinite))return null;
    const target={spot:[report.x,report.y,report.z,report.heading],home:peer.player.insideHome||null,
      context:null,source:'foot',updatedAt:now()};
    try{return validFoot(peer.player,target)?target:null;}catch{return null;}
  }
  function canAdmit(peer,report){const s=state(peer),target=foot(peer,report);if(!s||!target)return false;
    // Independent bounded arrival policy, not an original-game movement constant.
    return Math.hypot(target.spot[0]-s.target.spot[0],target.spot[1]-s.target.spot[1])<=2&&
      Math.abs(target.spot[2]-s.target.spot[2])<=3;
  }
  function observe(peer,report){
    const s=state(peer),target=foot(peer,report);if(!s||!target||(!s.applied&&!canAdmit(peer,report)))return false;
    const saved=normalize(peer.player.reconnectPlacement);s.changed=false;
    // Same restrictions as the existing idle-foot checkpoint policy.
    if(report.crouch!==true&&(report.act??0)===0){
      s.changed=!!saved.intent||!saved.foot||saved.foot.home!==target.home||
        saved.foot.spot.some((n,i)=>!Object.is(n,target.spot[i]));
      if(s.changed){saved.foot=target;saved.intent=null;peer.player.reconnectPlacement=saved;}
    }
    s.applied=true;return true;
  }
  return{begin,view,matches,packet,issue,canAdmit,observe,state};
}

module.exports={DEFAULT_SPOT,normalize,create,createBrowser};
