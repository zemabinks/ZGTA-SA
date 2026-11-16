#!/usr/bin/env node
'use strict';
// Execute the actual archived hurt/side routines offline. Raw source and
// generated observations stay local. This is not rendered or retail evidence.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {archivedModules}=require('./smoke_vehicle_dynamics');
const load=archivedModules(),T=load(85339),F=load(60662);
const folder=path.join(__dirname,'local-only/site/_next/static/chunks');
const source=fs.readdirSync(folder).filter(n=>n.startsWith('9737.')).map(n=>fs.readFileSync(path.join(folder,n),'utf8')).find(s=>s.includes('c6=function(e)'));
function method(marker,start=0){
 const a=source.indexOf(marker,start),b=source.indexOf('{',a);assert(a>=0&&b>a);let depth=0,q=null,escape=false;
 for(let i=b;i<source.length;i++){
  const c=source[i];if(q){if(escape)escape=false;else if(c==='\\')escape=true;else if(c===q)q=null;continue}
  if(['"',"'",'`'].includes(c)){q=c;continue}if(c==='{')depth++;else if(c==='}'&&!--depth)return source.slice(a,i+1);
 }throw Error('Unclosed archived method');
}
const hurt=method('hurt(e){',source.indexOf('c6=function(e)'));
const side=method('function aw('),a=source.indexOf('let am='),b=source.indexOf(';function ag',a);assert(a>=0&&b>a);
const geometry=source.slice(a,b)+';'+side;
let parried=false;
const context={e4:false,e1:-1,e0:50,eZ:100,tw:{light(){},douse(){}},ty:{whiff(){}},eb:true,
 T:{group:{position:new T.Pq0()}},W:0,F,nN:load(49368),performance:{now:()=>0},te:-Infinity,e8:true,
 td:{on:false},em:null,e_:null,C:{stunned:false,parry(){parried=true},flinch(){},loseHead(){return new T.Pq0()}},e9:0,e7:null,eL:true,
 rP:{I4:()=>false},r7:new Map(),ae:5/70*50,at:5/70*50,d:T,tt:null,ay:()=>'',M:{blood(){}},rw:load(19863),V:0,Z:0,eE:false,lr(){}};
vm.createContext(context);vm.runInContext(geometry+';var actor={'+hurt+'}',context);
const profiles=Array.from({length:16},(_,id)=>({id,blocks:F.U1(id).blocks}));
const policy=require('./weapon_inventory').createParry(profiles);let checks=0,cases=0;
function run(weapon,defenderWeapon,heading,offset,block=true){
 const target={x:Math.fround(1532.25),y:Math.fround(-2460.125)},attacker={x:target.x+offset[0],y:target.y+offset[1]};
 context.T.group.position.set(target.x,0,-target.y);context.W=heading;context.eb=block&&F.U1(defenderWeapon)?.blocks===true;
 context.e0=50;context.eZ=100;context.e1=-1;parried=false;
 context.actor.hurt(5,{weapon,from:new T.Pq0(attacker.x,0,-attacker.y)});
 const actual=policy(weapon,defenderWeapon,{walking:true,act:context.eb?28:36,heading,weapon:defenderWeapon},attacker,target);
 assert.equal(actual,parried,JSON.stringify({weapon,defenderWeapon,heading,offset}));
 if(parried){assert.equal(context.e0,50);assert.equal(context.eZ,100);checks+=2}checks++;cases++;
}
for(let weapon=0;weapon<=46;weapon++)for(let defender=0;defender<=15;defender++)
 for(const heading of [0,Math.PI/2,-Math.PI/2,Math.PI-1e-4,-Math.PI+1e-4])
  for(const angle of [-Math.PI,-3*Math.PI/4,-Math.PI/4,-.1,0,.1,Math.PI/4,3*Math.PI/4,Math.PI])
   run(weapon,defender,heading,[Math.sin(angle)*2,Math.cos(angle)*2]);
for(const weapon of [0,9,22])for(const heading of [0,Math.PI,1])run(weapon,0,heading,[0,0]);
for(const state of [{walking:false,act:28,heading:0},{walking:true,act:36,heading:0},{walking:true,act:28,heading:0,down:2},
 {walking:true,act:28,heading:NaN},{walking:true,act:true,heading:0}]){
 assert.equal(policy(0,0,state,{x:0,y:2},{x:0,y:0}),false);checks++;
}
assert.equal(require('./weapon_inventory').createParry([])(0,0,{walking:true,act:28,heading:0},{x:0,y:2},{x:0,y:0}),false);checks++;
const report={status:'PASS',checks,cases,sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),
 hurtSHA256:crypto.createHash('sha256').update(hurt).digest('hex'),limits:['Actual archived hurt and side routines with controlled actor/effects; no retail executable, render, network latency or body hitbox coverage']};
if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(report,null,2)+'\n',{mode:0o600});
console.log(`PASS archived front parry: ${checks} checks, ${cases} hurt decisions`);
