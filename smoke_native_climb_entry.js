#!/usr/bin/env node
'use strict';
// Execute the actual archived pedestrian entry predicate. The vehicle flag
// is controlled input, not an assertion about original retail handholds.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const game=path.join(__dirname,'local-only/site/_next/static/chunks'),file=fs.readdirSync(game).filter(v=>v.endsWith('.js')).map(v=>path.join(game,v)).find(v=>fs.readFileSync(v,'utf8').includes('eA=e=>{let t,l=C?{jump:'));
assert(file,'Archived climb entry missing');const source=fs.readFileSync(file,'utf8');
const start=source.indexOf('eA=e=>{',source.indexOf('c6=function(e)'))+3,opening=source.indexOf('{',start);
assert(start>=3&&opening>start);let depth=0,quote=null,escape=false,end;
for(let i=opening;i<source.length;i++){
 const c=source[i];if(quote){if(escape)escape=false;else if(c==='\\')escape=true;else if(c===quote)quote=null;continue}
 if(c==='"'||c==="'"||c==='`'){quote=c;continue}if(c==='{')depth++;else if(c==='}'&&!--depth){end=i+1;break}
}
assert(end,'Unbalanced archived entry');const entry=source.slice(start,end),T=require('./smoke_vehicle_dynamics').archivedModules()(85339),cases=[];
for(const vehicle of [false,true])for(const mode of ['normal','worn','flying','dead','missing-animation']){
 const context={C:mode==='missing-animation'?null:{lasts:()=>.5},e1:mode==='dead'?0:-1,tf:{worn:mode==='worn',on:mode==='flying'},d:T,
  n5:[-.4,-1.1],n3:[-.4,0],n4:[.15,1],n6:[.5,0],n7:.25,re:{JUMP:20,HANG:21,PULL:22,EDGE:23,STAND:24,VAULT:25},em:null,eE:true,Y:true,V:2,K:3,ep:new T.Pq0(1,0,0),eN:()=>{}};
 const original=vm.runInNewContext('('+entry+')',context),ledge={hold:new T.Pq0(0,1.8,-.8),into:new T.Pq0(0,0,-1),feet:new T.Pq0(),heading:0,high:false,vault:!vehicle,vehicle};
 cases.push({vehicle,mode,accepted:original(ledge),part:context.em?.part??null});
}
fs.writeFileSync(process.argv[2],JSON.stringify({scope:'Actual archived pedestrian entry with controlled clip availability; not retail runtime',sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),entrySHA256:crypto.createHash('sha256').update(entry).digest('hex'),start,end,cases}),{mode:0o600});
console.log('Recorded',cases.length,'actual archived climb entry cases');
