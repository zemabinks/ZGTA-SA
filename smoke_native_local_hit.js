#!/usr/bin/env node
'use strict';
// Actual archived hurt method with controlled actor/animator/effect callbacks.
// This isolates its decision rules; it does not execute a rendered retail game.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {archivedModules}=require('./smoke_vehicle_dynamics'),load=archivedModules(),T=load(85339),nN=load(49368),rT=load(46819),rw=load(19863);
const folder=path.join(__dirname,'local-only/site/_next/static/chunks');
const source=fs.readdirSync(folder).filter(v=>v.endsWith('.js')).map(v=>fs.readFileSync(path.join(folder,v),'utf8')).find(v=>v.includes('c6=function(e)'));
assert(source);const start=source.indexOf('hurt(e){',source.indexOf('c6=function(e)')),opening=source.indexOf('{',start);
let depth=0,quote=null,escape=false,end;
for(let i=opening;i<source.length;i++){
 const c=source[i];if(quote){if(escape)escape=false;else if(c==='\\')escape=true;else if(c===quote)quote=null;continue}
 if(c==='"'||c==="'"||c==='`'){quote=c;continue}if(c==='{')depth++;else if(c==='}'&&!--depth){end=i+1;break}
}
assert(start>=0&&end>start);const hurt=source.slice(start,end);
function literal(marker){const at=source.indexOf(marker);assert(at>=0);const first=at+marker.length,last=source.indexOf('])',first);assert(last>first);return vm.runInNewContext(source.slice(first,last+1));}
const deaths=new Set(literal('r9=new Set(')),forces=new Map(literal('r7=new Map('));
const ayStart=source.indexOf('let ay=')+7,ayEnd=source.indexOf(';function ab',ayStart);assert(ayStart>=7&&ayEnd>ayStart);
const choose=Function('rT','an','r9','return ('+source.slice(ayStart,ayEnd)+')')(rT,['koSkidBack','koSpinR','koSkidFront','koSpinL','floorHit','floorHitF'],deaths);
const groups=[];
function group(name,inputs){
 let output,context;
 const C={stunned:false,flinch(kind,stun=false){output.flinch=kind;output.stun=stun;this.stunned=stun},loseHead(){output.loseHead=true;return new T.Pq0()}};
 context={e4:false,e1:-1,e0:0,eZ:100,tw:{light(){},douse(){}},ty:{whiff(){}},eb:false,T:null,W:0,F:{U1:()=>null},aw:()=>0,nN,performance:{now:()=>0},te:-Infinity,e8:true,td:{on:false},em:null,e_:null,C,e9:0,e7:null,eL:true,rP:{I4:()=>false},r7:forces,ae:5/70*50,at:5/70*50,d:T,tt:null,ay:choose,M:{blood(){}},rw,
  lr(kind){output.death=kind;context.eZ=0;context.e1=0}};
 const actor=vm.runInNewContext('({'+hurt+'})',context),frames=[];
 for(const input of inputs){
  output={flinch:null,stun:false,death:null,impulse:null,loseHead:false};context.e1=input.wasAlive?-1:0;context.e0=input.armour;context.eZ=input.healthBefore;
  context.tt=null;context.C.stunned=false;context.e8=input.stun;context.td.on=input.swimming;context.em=input.climbing?{}:null;context.e_=input.stealth?{}:null;
  context.T=input.hasActor?{group:{position:new T.Pq0(...input.target)}}:null;context.aw=()=>input.side;context.V=input.still?0:2;context.Z=0;context.eE=input.crouched;context.performance.now=()=>input.now;
  actor.hurt(input.damage,{weapon:input.weapon,piece:input.piece,quiet:input.quiet,from:input.source?new T.Pq0(...input.source):null});
  if(context.tt)output.impulse=[context.tt.away.x,context.tt.up,context.tt.away.z];
  output.until=Number.isFinite(context.te)?context.te:null;
  frames.push({input:{...input,side:input.hasActor?input.side:0,healthAfter:context.eZ},expected:output});
 }
 groups.push({name,frames});
}
function input(index){
 const mode=index%8;
 return {weapon:index*97%55,damage:[5,25,150][index%3],healthBefore:index%3===0?10:100,armour:index%5===0?20:0,
  side:index%4,piece:[0,3,5,6,7,8,9][index%7],quiet:mode===4,wasAlive:mode!==7,stun:mode!==5,still:index%3===0,crouched:index%4===0,
  swimming:mode===1,climbing:mode===2,stealth:mode===3,hasActor:mode!==6,source:index%11===0?null:[-3,0,4],target:[2,.1,-3],now:1000};
}
for(let index=0;index<1680;index++)group('case'+index,[input(index)]);
for(const weapon of [0,22,24,31,35])for(const still of [false,true]){
 const times=[0,0,100,1499,1500,1501,2499,2500,2501,5001];
 group('cooldown'+weapon+'/'+still,times.map(now=>({...input(0),weapon,still,healthBefore:100,armour:0,damage:5,now,source:[0,0,0],quiet:false,wasAlive:true,crouched:false})));
}
fs.writeFileSync(process.argv[2],JSON.stringify({sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),hurtSHA256:crypto.createHash('sha256').update(hurt).digest('hex'),groups}),{mode:0o600});
console.log('Recorded',groups.length,'actual archived hit groups,',groups.reduce((n,g)=>n+g.frames.length,0),'decision frames');
