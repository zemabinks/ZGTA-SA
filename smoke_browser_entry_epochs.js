#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Independently authored async owners exercise the real source transformer and
// coordinator. No original client source/assets, network, timers or engine.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const hook=require('./browser_recovery_hook'),{coordinator,TOKEN}=require('./browser_recovery');
let checks=0;const cases=[];const check=(v,n)=>{checks++;assert(v,n);};
const same=(v,w,n)=>{checks++;assert.deepEqual(v,w,n);};
const sha=v=>crypto.createHash('sha256').update(v).digest('hex');
const authored={
 teleport:'onTeleport:e=>{if(!active)return;at=e}',
 normal:'mE=async()=>{if(dead||mC)return;mC=true;const model=await load("normal").catch(()=>null);if(mC=!1,!model||dead||!sameBody){model?.dispose();return;}take("normal",model)}',
 spawned:'mR=async e=>{if(dead||mC)return;mC=true;const model=await load("spawned").catch(()=>null);if(mC=!1,!model||dead||!sameBody){model?.dispose();return;}take("spawned",model)}',
};
const fixtureSource='globalThis.owner={'+authored.teleport+'};\nglobalThis.'+authored.normal+';\nglobalThis.'+authored.spawned+';';
const identities=[
 {kind:'teleport',marker:hook.MARKER,length:authored.teleport.length,sha256:sha(authored.teleport)},
 {kind:'entry',marker:'mE=async()=>{',length:authored.normal.length,sha256:sha(authored.normal)},
 {kind:'entry',marker:'mR=async e=>{',length:authored.spawned.length,sha256:sha(authored.spawned)},
];
function ready(connection='a'.repeat(24)){
 const c=coordinator({send(){}}),scope={connection,revision:0};c.outgoing({t:'hi'},true);
 c.receive({t:'hello',browserRecovery:1,browserPlacement:scope,life:[100,0]},()=>{});
 c.receive({t:'all',protocol:38,number:1,id:'1',cars:[],vehicles:[]},()=>{});
 const tp={t:'tp',x:100,y:100,z:20,h:0,g:1,browserPlacement:scope};
 c.receive(tp,()=>c.didApplyTeleport({x:100,y:100,z:20,heading:0,ground:true}));
 c.outgoing({t:'me',walking:true,x:100,y:100,z:20,heading:0,health:100,air:false},true);
 c.receive({t:'browserPlacement',accepted:true,browserPlacement:scope},()=>{});return c;
}
function advance(c){const next={...c.placement,revision:c.placement.revision+1};
 c.receive({t:'tp',x:101,y:101,z:20,h:0,g:1,browserPlacement:next},()=>c.didApplyTeleport({x:101,y:101,z:20,heading:0,ground:true}));return next;}
function admit(c){c.outgoing({t:'me',walking:true,x:101,y:101,z:20,heading:0,health:100,air:false},true);
 c.receive({t:'browserPlacement',accepted:true,browserPlacement:c.placement},()=>{});}
function carrier({instrumented=true,legacy=false,missingAPI=false}={}){
 let current=ready();const loads=[],takes=[],disposed=[];
 const context={active:true,at:null,mC:false,dead:false,sameBody:true,
   load:kind=>new Promise((resolve,reject)=>loads.push({kind,resolve,reject})),take:(kind,model)=>takes.push({kind,id:model.id})};
 if(!missingAPI)context.ZGTABrowserRecovery={registerHook:token=>check(token===TOKEN,'Matching complete-hook registration'),didApplyTeleport(){},
   captureActionGrant:()=>legacy?{legacy:true}:current.actionGrant(),isActionGrantCurrent:g=>legacy?g?.legacy===true:current.ownsActionGrant(g)};
 vm.runInNewContext(instrumented?hook.instrument(fixtureSource,identities):fixtureSource,context);
 function finish(index,id='model',onDispose){loads[index].resolve({id,dispose(){disposed.push(id);onDispose?.();}});}
 return{context,loads,takes,disposed,finish,get current(){return current;},replace(c){current=c;}};
}
async function scenario(name,body){const start=checks;await body();cases.push({name,checks:checks-start});}
async function main(){
 same(hook.TOKEN,TOKEN,'Hook/coordinator registration versions must match');
 check(TOKEN!=='normal-teleport-completion-v1','Old TP-only registration cannot enable new coordinator');
 for(const name of ['mE','mR']){
  await scenario(name+' historical async ownership negative',async()=>{
   const h=carrier({instrumented:false}),work=h.context[name]();advance(h.current);admit(h.current);h.finish(0,'old');await work;
   check(h.takes.length===1&&h.disposed.length===0,'Unfenced authored historical task commits across a new placement');
  });
  await scenario(name+' pending refusal and original busy serialization',async()=>{
   const h=carrier();advance(h.current);await h.context[name]();
   check(!h.context.mC&&h.loads.length===0&&h.takes.length===0,'Pending task returns before setting busy or loading');
   admit(h.current);const first=h.context[name]();await h.context[name]();
   check(h.context.mC&&h.loads.length===1,'Existing busy owner prevents duplicate load');h.finish(0);await first;
   check(!h.context.mC&&h.takes.length===1&&h.disposed.length===0,'Normal current task admitted once');
  });
  for(const interruption of ['teleport','new connection','disconnect','death','body replacement','resource failure']){
   await scenario(name+' '+interruption,async()=>{
    const h=carrier(),work=h.context[name]();same(h.loads.length,1,'Normal task starts one actual loader');
    if(interruption==='teleport'){advance(h.current);admit(h.current);}
    if(interruption==='new connection'){h.current.close();h.replace(ready('b'.repeat(24)));}
    if(interruption==='disconnect')h.current.close();
    if(interruption==='death')h.context.dead=true;
    if(interruption==='body replacement')h.context.sameBody=false;
    if(interruption==='resource failure')h.loads[0].reject(Error('Authored missing resource'));else h.finish(0,'stale');
    await work;
    check(!h.context.mC&&h.takes.length===0,'Rejected task releases busy and never takes body');
    same(h.disposed.length,interruption==='resource failure'?0:1,'Only an existing rejected model is disposed, exactly once');
    h.context.dead=false;h.context.sameBody=true;
    if(interruption==='disconnect')h.replace(ready('c'.repeat(24)));
    const retry=h.context[name]();same(h.loads.length,2,'Fresh ordinary user task can retry');h.finish(1,'fresh');await retry;
    check(!h.context.mC&&h.takes.length===1&&h.takes[0].id==='fresh','Only the fresh task owns admission');
   });
  }
  await scenario(name+' disposal reentrancy preserves newer busy owner',async()=>{
   const h=carrier(),old=h.context[name]();h.current.close();h.replace(ready('b'.repeat(24)));
   let fresh;h.finish(0,'old',()=>{fresh=h.context[name]();});await old;
   check(h.context.mC&&h.loads.length===2&&h.takes.length===0,'Disposal callback can start new owner without old tail clearing it');
   h.finish(1,'new');await fresh;check(!h.context.mC&&h.takes.length===1&&h.takes[0].id==='new','New owner completes exactly once');
  });
  for(const mode of ['unnegotiated legacy','no adapter'])await scenario(name+' '+mode,async()=>{
   const h=carrier({legacy:mode==='unnegotiated legacy',missingAPI:mode==='no adapter'}),work=h.context[name]();h.finish(0);await work;
   check(h.takes.length===1&&!h.context.mC&&h.disposed.length===0,'Existing unnegotiated behavior preserved explicitly');
  });
 }
 await scenario('all-source fingerprint atomicity and independent guard preservation',()=>{
  for(const identity of identities){
   const start=fixtureSource.indexOf(identity.marker),end=start+identity.length;
   const changed=fixtureSource.slice(0,end-1)+' '+fixtureSource.slice(end-1);
   checks++;assert.throws(()=>hook.instrument(changed,identities),'Any changed seam rejects whole capability');
   checks++;assert.throws(()=>hook.instrument(fixtureSource+'\n'+fixtureSource.slice(start,end),identities),'Any duplicated seam rejects whole capability');
  }
  const transformed=hook.instrument(fixtureSource,identities);
  check(transformed.includes('!model||dead||!sameBody'),'All independently authored existing guards survive');
  check(transformed.includes('model?.dispose();return;'),'Existing disposal/error path survives');
  check(!transformed.includes('dispatchEvent')&&!transformed.includes('local=true'),'No input or identity repair is inserted');
 });
 const out=path.join(__dirname,'local-only/research/browser-recovery-116/entry-epoch-audit');fs.mkdirSync(out,{recursive:true});
 const report={passed:true,checks,cases,scope:'authored asynchronous owners + actual transformer/coordinator; no original client, asset or live execution',
   hashes:Object.fromEntries(['browser_recovery.js','browser_recovery_hook.js','smoke_browser_entry_epochs.js'].map(n=>[n,sha(fs.readFileSync(path.join(__dirname,n)))]))};
 fs.writeFileSync(path.join(out,'authored-report.json'),JSON.stringify(report,null,2)+'\n');
 console.log('Browser entry epochs PASS',checks,'checks /',cases.length,'scenarios');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
