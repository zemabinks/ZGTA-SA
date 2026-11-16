#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const folder=path.join(__dirname,'local-only/site/_next/static/chunks'),file=fs.readdirSync(folder).find(n=>n.startsWith('9737.')),source=fs.readFileSync(path.join(folder,file),'utf8');
function method(start,end){const a=source.indexOf(start,1720000),b=source.indexOf(end,a);assert(a>=0&&b>a,start);return source.slice(a,b+1)}
const hurt=method('hurt(e){','},rammed('),health=method('set health(value){','},get armour'),armour=method('set armour(value){','},get dead'),godly=method('set godly(on){','},show('),respawn=method('respawn(e){','},steer(');
const deathStart=source.indexOf('lr=(e,t)=>{',1720000)+'lr='.length,deathEnd=source.indexOf(';return{setGlassBlow',deathStart);assert(deathStart>0&&deathEnd>deathStart);const death=source.slice(deathStart,deathEnd);
const context={eZ:100,e0:0,e1:-1,e4:false,events:[],td:{on:false,revive(){}},tw:{light(){context.events.push('fire')},douse(){context.events.push('douse')},extinguish(){}},ty:{whiff(){context.events.push('gas')},clear(){}},tf:{stop(){},wear(){}},ti:{reset(){}},C:{parry(){context.events.push('parry')},die(){context.events.push('death')},revive(){},rest(){}},T:{group:{position:{}}},eb:false,W:0,V:0,Z:0,eE:false,te:0,e8:false,aw:()=>0,F:{U1:w=>({use:w>=0&&w<=15?'melee':'gun'})},nN:{be:()=>({kind:null,until:0,stun:false}),F4:()=>false},rw:{oH:53},r7:new Map(),ay:()=> 'koFront',performance:{now:()=>1000},t6(){},_(){},y(){},eR:false,eL:false,ex:false,eS:null,e_:null,ez:null,tL:null,tO:null};
context.lr=vm.runInNewContext('('+death+')',context);
const getters=[method('get health(){','},set health'),method('get armour(){','},set armour'),method('get dead(){','},get fallen')];
const actor=vm.runInNewContext('({'+[hurt,health,armour,godly,respawn,...getters].join(',')+',plainView(){}})',context);
const cases=[];
for(const hp of [1,1.05,33.3,100])for(const ap of [0,.15,100])for(const damage of [.01,.1,.5,1.25,17.5,125])for(const weapon of [-1,0,9,22,37,41,42,49,50,53,54])for(const mode of ['normal','quiet','swimming','parry','quietParry','godly','dead','godlyDead']){
 const quiet=mode==='quiet'||mode==='quietParry',parry=mode==='parry'||mode==='quietParry',swimming=mode==='swimming',dead=mode==='dead'||mode==='godlyDead',invulnerable=mode==='godly'||mode==='godlyDead';
 Object.assign(context,{eZ:dead?0:hp,e0:ap,e1:dead?0:-1,e4:false,eb:parry,events:[]});context.td.on=swimming;actor.godly=invulnerable;
 actor.hurt(damage,{weapon,quiet,from:{}});
 cases.push({hp,ap,damage,weapon,quiet,parry,swimming,dead,godly:invulnerable,expected:{health:context.eZ,armour:context.e0,dead:context.e1>=0,events:context.events,wireHealth:context.e1>=0?0:Math.max(1,Math.ceil(context.eZ)),wireArmour:Math.ceil(context.e0)}});
}
const sequences=[];
for(const ap of [0,.15,5.5,100]){
 Object.assign(context,{eZ:100,e0:ap,e1:-1,e4:false,eb:false,events:[]});context.td.on=false;
 const states=[];for(let i=0;i<1200;i++){actor.hurt(.1,{weapon:22,quiet:true});if(i%37===0||i===1199)states.push({index:i,health:context.eZ,armour:context.e0,dead:context.e1>=0})}
 sequences.push({armour:ap,states});
}
function callback(marker){const a=source.indexOf(marker,2000000)+marker.length;let open=source.indexOf('{',a),depth=0,quote=null,escape=false;for(let i=open;i<source.length;i++){const ch=source[i];if(quote){if(escape)escape=false;else if(ch==='\\')escape=true;else if(ch===quote)quote=null;continue}if(ch==='\"'||ch==="'"||ch==='`'){quote=ch;continue}if(ch==='{')depth++;else if(ch==='}'&&--depth===0)return source.slice(a,i+1)}throw Error('Unterminated callback')}
const shotSource=callback('onShot:');context.c6=actor;context.l_=true;context.lA=true;context.ub={on:false};context.sv={current:false};context.cj={kind:'car',speed:1};context.mK=()=>{context.lT=false;context.dF=null};context.gG=()=>{context.ub.on=false};
const shot=vm.runInNewContext('('+shotSource+')',context),fatalCases=[];
for(const hp of[1,10.1,100])for(const ap of[0,5.5,100])for(const damage of[.1,5,10,120])for(const speed of[.5,.5001,-1])for(const kind of['car','bike']){
 Object.assign(context,{eZ:hp,e0:ap,e1:-1,e4:false,eb:false,lT:true,dF:null,events:[]});context.td.on=false;context.cj.kind=kind;context.cj.speed=speed;
 shot({from:'peer',weapon:22,damage,car:false});fatalCases.push({hp,ap,damage,speed,kind,deferred:context.dF!==null,until:context.dF?context.dF.until:null});
}
const fireStart=source.indexOf('tw=(t=0,l=null,n=0,r=0,'),fireEnd=source.indexOf('),ty=',fireStart),gasStart=fireEnd+'),ty='.length,gasEnd=source.indexOf('),tb=',gasStart);
assert(fireStart>=0&&fireEnd>fireStart&&gasEnd>gasStart);
const fireExpression=source.slice(fireStart+3,fireEnd+1),gasExpression=source.slice(gasStart,gasEnd+1),effects=[];
for(const hz of [15,30,60,90,120,144])for(const mode of ['burn','douse','relight','extinguish','spray','volume','mixed']){
 const scope={Math:Object.create(Math)};scope.Math.random=()=>.5;
 const fire=vm.runInNewContext(fireExpression,scope),gas=vm.runInNewContext(gasExpression,scope),steps=[];
 for(let tick=0;tick<hz*4;tick++){
  const actions=[];
  function event(type,by=null,value=null){actions.push({type,by,value});if(type==='light')fire.light(by);if(type==='douse')fire.douse(value);if(type==='extinguish')fire.extinguish();if(type==='whiff')gas.whiff(by,value);if(type==='clearGas')gas.clear();}
  if(tick===0&&['burn','douse','relight','extinguish','mixed'].includes(mode))event('light','firePeer');
  if(tick===Math.floor(hz/2)&&mode==='douse')event('douse',null,.3);
  if(tick===hz&&mode==='douse')event('douse',null,.3);
  if(tick===hz&&mode==='relight')event('light','secondPeer');
  if(tick===hz*3&&mode==='relight')event('light','secondPeer');
  if(tick===hz&&mode==='extinguish')event('extinguish');
  if(tick===0&&mode==='spray')event('whiff','sprayPeer',false);
  if((mode==='volume'||mode==='mixed')&&tick<hz*2)event('whiff','gasPeer',true);
  const burnDamage=fire.step(1/hz),gasDamage=gas.step(1/hz);
  steps.push({delta:1/hz,actions,burnDamage,gasDamage,burning:fire.on,coughing:gas.on,fireSource:fire.by,gasSource:gas.by});
 }
 effects.push({hz,mode,steps});
}
const output={sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),expressionsSHA256:crypto.createHash('sha256').update([hurt,health,armour,godly,respawn,death,...getters,shotSource,fireExpression,gasExpression].join('\n')).digest('hex'),cases,sequences,fatalCases,effects};
fs.mkdirSync(path.dirname(process.argv[2]),{recursive:true});fs.writeFileSync(process.argv[2],JSON.stringify(output)+'\n',{mode:0o600});console.log('Recorded actual archived fractional vitals:',cases.length,'cases and',sequences.length,'fractional sequences');
