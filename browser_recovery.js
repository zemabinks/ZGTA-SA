// SPDX-License-Identifier: AGPL-3.0-only
// Independent self-host transport adapter. No engine state or input is injected.
(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  else api.install(root);
})(typeof globalThis==='object'?globalThis:this,function(){
  'use strict';
  const TOKEN='normal-teleport-and-entry-v2';
  const valid=v=>v&&typeof v==='object'&&!Array.isArray(v)&&typeof v.connection==='string'&&
    /^[A-Za-z0-9_-]{24}$/.test(v.connection)&&Number.isSafeInteger(v.revision)&&v.revision>=0;
  const same=(a,b)=>valid(a)&&valid(b)&&a.connection===b.connection&&a.revision===b.revision;
  const finite=v=>typeof v==='number'&&Number.isFinite(v);
  function coordinator({send,status=()=>{},isCurrent=()=>true,clock=()=>Date.now(),onReady=()=>{}}={}){
    let phase='legacy',scope=null,baseline=false,delivery=null,applied=null,lastRequest=-Infinity;
    const current=()=>isCurrent()&&phase!=='closed';
    const note=text=>status(text);
    const fail=text=>{phase='failed';delivery=null;applied=null;note(text);};
    function outgoing(value,hookReady){
      if(!current())return null;
      if(value?.t==='hi'){
        if(phase==='legacy'&&hookReady){phase='negotiating';note('Reconnecting: waiting for the server placement.');
          return{...value,browserRecovery:1};}
        return value;
      }
      if(phase==='legacy')return value;
      if(value?.t==='ping')return value;
      if(phase==='ready')return value?.t==='me'?{...value,browserPlacement:{...scope}}:value;
      if(value?.t!=='me'||phase==='failed')return null;
      // A real gameplay report is the only trigger for retrying an ignored TP.
      // No timer, synthetic report, old-role replay or replacement socket exists.
      if(!baseline||!scope)return null;
      if(applied&&same(applied,scope)&&value.walking===true&&value.driving!==true&&
        !value.passenger&&!value.riding&&!value.on&&!value.vehicle&&value.air!==true&&finite(value.health)&&value.health>0&&
        [value.x,value.y,value.z,value.heading].every(finite)){
        phase='admitting';return{...value,browserPlacement:{...scope}};
      }
      if(!applied&&clock()-lastRequest>=500){lastRequest=clock();
        send({t:'browserPlacementRequest',browserPlacement:{...scope}});}
      return null;
    }
    function receive(value,deliver){
      if(!current())return;
      if(value?.t==='hello'){
        if(value.browserRecovery!==1){
          if(value.browserRecovery!==undefined)return fail('Recovery stopped: malformed server capability.');
          if(phase==='negotiating'){phase='legacy';note('');}
          deliver();return;
        }
        if(!valid(value.browserPlacement)||!Array.isArray(value.life)||!finite(value.life[0]))
          return fail('Recovery stopped: invalid server placement. Reload to reconnect.');
        if(scope&&!same(scope,value.browserPlacement)){
          // A same-socket duplicate hello must never rewind a newer teleport.
          if(scope.connection!==value.browserPlacement.connection)
            return fail('Recovery stopped: the server changed this connection. Reload to reconnect.');
          if(value.browserPlacement.revision>scope.revision)
            return fail('Recovery stopped: unexpected placement revision.');
          deliver();return;
        }
        if(!scope){scope={...value.browserPlacement};phase='pending';}
        deliver();
        if(current()&&value.life[0]<=0)fail('Recovery stopped: the server character is dead. A server-authorized respawn is required.');
        return;
      }
      if(phase==='legacy'){deliver();return;}
      if(value?.t==='all'){
        deliver();if(current()&&scope&&value.protocol===38&&Number.isSafeInteger(value.number)&&value.number>0&&
          value.id===String(value.number)&&Array.isArray(value.cars)&&Array.isArray(value.vehicles))baseline=true;return;
      }
      if(value?.t==='tp'){
        const next=value.browserPlacement;
        if(!valid(next)||!scope||next.connection!==scope.connection||next.revision<scope.revision||
          ![value.x,value.y,value.z,value.h].every(finite))return;
        if(next.revision===scope.revision&&applied)return;
        scope={...next};applied=null;phase='applying';
        const witness={value,seen:false};delivery=witness;
        try{deliver();}catch(error){fail('Recovery stopped: the normal teleport callback failed.');throw error;}
        finally{if(delivery===witness)delivery=null;}
        if(!current()||phase!=='applying'||!same(scope,value.browserPlacement))return;
        if(witness.seen&&baseline){applied={...scope};phase='foot';
          note('Reconnecting: waiting for the actual foot report.');}
        else{phase='pending';note('Waiting for the active character to apply the server placement.');}
        return;
      }
      if(value?.t==='browserPlacement'){
        if(!same(scope,value.browserPlacement)||!applied||!baseline)return;
        if(value.accepted!==true)return fail('Recovery stopped: the server refused the foot placement.');
        phase='ready';note('');if(current())onReady();return;
      }
      deliver();
    }
    function didApplyTeleport(value){
      const d=delivery;if(!current()||phase!=='applying'||!d||!value)return false;
      const raw=d.value;
      if(!same(raw.browserPlacement,scope)||value.x!==raw.x||value.y!==raw.y||value.z!==raw.z||
        value.heading!==raw.h||value.ground!==(raw.g===1))return false;
      d.seen=true;return true;
    }
    function actionGrant(){if(!current())return null;
      if(phase==='legacy')return{legacy:true};
      return phase==='ready'?{...scope}:null;
    }
    function ownsActionGrant(grant){return current()&&(grant?.legacy===true?phase==='legacy':
      phase==='ready'&&same(grant,scope));}
    return{outgoing,receive,didApplyTeleport,actionGrant,ownsActionGrant,
      close(){phase='closed';delivery=null;scope=null;applied=null;baseline=false;},
      get phase(){return phase;},get placement(){return scope?{...scope}:null;}};
  }
  function install(root){
    if(root.ZGTABrowserRecovery||typeof root.WebSocket!=='function')return;
    const Native=root.WebSocket;let active=null,hookReady=false,established=false;
    function status(text){
      const doc=root.document;if(!doc)return;
      let element=doc.getElementById('zgta-browser-recovery');
      if(!element&&text){element=doc.createElement('div');element.id='zgta-browser-recovery';
        element.setAttribute('role','status');element.style.cssText='position:fixed;top:12px;left:12px;right:12px;z-index:2147483646;padding:10px;background:#16202ee8;color:white;font:14px system-ui;pointer-events:none';
        (doc.body||doc.documentElement).appendChild(element);}
      if(element){element.textContent=text;element.hidden=!text;}
    }
    root.addEventListener?.('error',event=>{
      if(typeof event.target?.src==='string'&&/\/_next\/static\/chunks\/9737\.[a-f0-9]+\.js(?:$|\?)/.test(event.target.src))
        status('Local browser recovery is unavailable: restore the verified archived client and reload.');
    },true);
    root.ZGTABrowserRecovery=Object.freeze({registerHook(token){if(token===TOKEN)hookReady=true;},
      didApplyTeleport(value){return active?.recovery.didApplyTeleport(value)||false;},
      captureActionGrant(){return active?active.recovery.actionGrant():hookReady?null:{legacy:true};},
      isActionGrantCurrent(grant){return active?active.recovery.ownsActionGrant(grant):!hookReady&&grant?.legacy===true;}});
    class RecoverySocket extends Native{
      constructor(url,protocols){
        if(protocols===undefined)super(url);else super(url,protocols);
        let target;try{target=new URL(url,root.location.href);}catch{return;}
        const own=target.pathname==='/api/world/live'&&target.host===root.location.host&&
          target.protocol===(root.location.protocol==='https:'?'wss:':'ws:');
        if(!own)return;
        if(active)active.recovery.close();
        let handler=null;
        const session={socket:this,recovery:null,pointerLockOwner:null};active=session;
        session.recovery=coordinator({send:value=>Native.prototype.send.call(this,JSON.stringify(value)),
          status,onReady:()=>{established=true;},isCurrent:()=>active===session&&this.readyState===Native.OPEN});
        this._zgtaRecovery=session.recovery;
        Object.defineProperty(this,'onmessage',{configurable:true,get:()=>handler,set:value=>{handler=value;}});
        Native.prototype.addEventListener.call(this,'message',event=>{
          if(active!==session)return;
          let value;try{value=JSON.parse(event.data);}catch{handler?.call(this,event);return;}
          session.recovery.receive(value,()=>handler?.call(this,event));
        });
        Native.prototype.addEventListener.call(this,'close',()=>{session.recovery.close();if(active===session){active=null;
          // Use the existing browser's ordinary loss/pause lifecycle. Never
          // synthesize releases, mutate its held state, or auto-request lock.
          if(established&&session.pointerLockOwner&&root.document?.pointerLockElement===session.pointerLockOwner){
            try{const result=root.document.exitPointerLock?.();result?.catch?.(()=>{});}catch{}
          }
          status('Disconnected: waiting for the normal game reconnect.');}});
      }
      send(data){
        if(!this._zgtaRecovery)return super.send(data);
        let value;try{value=JSON.parse(data);}catch{
          if(this._zgtaRecovery.phase==='legacy')super.send(data);return;
        }
        if(value?.t==='hi'&&!hookReady)status('Verified reconnect adapter unavailable; using the existing legacy connection.');
        const packet=this._zgtaRecovery.outgoing(value,hookReady);
        if(packet){
          const lock=root.document?.pointerLockElement;
          if(active?.socket===this&&packet.t==='me'&&packet.paused!==true&&
            (packet.walking===true||packet.driving===true)&&lock?.tagName==='CANVAS')active.pointerLockOwner=lock;
          super.send(JSON.stringify(packet));
        }
      }
    }
    root.WebSocket=RecoverySocket;
  }
  return{coordinator,install,TOKEN};
});
