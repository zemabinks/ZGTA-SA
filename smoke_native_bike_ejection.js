#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const load=require('./smoke_vehicle_dynamics').archivedModules(),T=load(85339),force=load(52431).Q;
const folder=path.join(__dirname,'local-only/site/_next/static/chunks'),file=fs.readdirSync(folder).find(n=>n.startsWith('2540.'));
const source=fs.readFileSync(path.join(folder,file),'utf8');
const a=source.indexOf('if("bike"===d.kind&&ti&&!tu?'),b=source.indexOf(',ev=',a);assert(a>=0&&b>a);
// The original if condition also updates car rollover. Complete its unused
// consequent with an empty body to isolate the actual bike expression.
const rollover=source.slice(a,b)+'){}';
const impacts=[];
for(const model of [448,468,481,509,510,521,581])for(const mass of [100,150,500,800])
 for(let index=0;index<150;index++){
  const q=new T.PTz().setFromAxisAngle(new T.Pq0(1,0.3,0.7).normalize(),index*.071),
   way=new T.Pq0(Math.sin(index*.37),Math.cos(index*.23),Math.sin(index*.57)).normalize(),
   forward=new T.Pq0(0,0,-1).applyQuaternion(q),right=new T.Pq0(1,0,0).applyQuaternion(q),up=new T.Pq0(0,1,0).applyQuaternion(q),
   intensity=[0,1,2,10,50,100,200,500,1000,4000][index%10];
  impacts.push({model,mass,intensity,way:way.toArray(),forward:forward.toArray(),right:right.toArray(),up:up.toArray(),expected:force({id:model,mass,intensity,way,forward,right,up})});
 }
const cases=[];
for(const hz of [20,30,60,90,120])for(const mode of ['upright','fallen','inverted','fast','airborne','interrupt']){
 const context={d:{kind:'bike'},ti:false,tu:null,ew:0,h:1,u:{x:0,y:0,z:0},n:T,e:0};vm.createContext(context);const rows=[];
 for(let tick=0;tick<hz*2;tick++){
  const up=mode==='upright'?1:mode==='inverted'?-.1001:.3,contact=mode!=='airborne'&&!(mode==='interrupt'&&tick%Math.max(1,hz/4)<2),speed=mode==='fast'?3.01:1;
  Object.assign(context,{h:up,ti:contact,u:{x:speed,y:0,z:0},e:1/hz});
  vm.runInContext(rollover,context);const event=context.tu;
  rows.push({delta:1/hz,up,contact,speed,expected:event?{force:event.force,velocity:event.velocity.toArray()}:null});context.tu=null;
 }
 cases.push({hz,mode,rows});
}
fs.writeFileSync(process.argv[2],JSON.stringify({sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),forceSHA256:crypto.createHash('sha256').update(force.toString()).digest('hex'),impacts,cases})+'\n',{mode:0o600});
console.log('Recorded actual bike ejection:',impacts.length,'force cases;',cases.length,'rollover sequences');
