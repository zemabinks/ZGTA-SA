#!/usr/bin/env node
'use strict';
// Execute only bounded functions extracted from the owner's archived client.
// No original JavaScript or generated golden data belongs in the source repo.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=__dirname,folder=path.join(root,'local-only/site/_next/static/chunks');
const find=prefix=>path.join(folder,fs.readdirSync(folder).find(n=>n.startsWith(prefix)));
const main=fs.readFileSync(find('9737.'),'utf8'),vehicle=fs.readFileSync(find('2540.'),'utf8');
function arrow(source,marker,after=0){
 const a=source.indexOf(marker,after);assert(a>=0,marker);const start=a+marker.length;
 let open=source.indexOf('{',start),depth=0,quote=null,escaped=false;
 for(let i=open;i<source.length;i++){
  const ch=source[i];if(quote){if(escaped)escaped=false;else if(ch==='\\')escaped=true;else if(ch===quote)quote=null;continue;}
  if(ch==='"'||ch==="'"||ch==='`'){quote=ch;continue;}
  if(ch==='{')depth++;else if(ch==='}'&&--depth===0)return source.slice(start,i+1);
 }
 throw Error('Unterminated archived function '+marker);
}
const hitAdapter=arrow(main,'else if("hit"===l.t)('),vehicleCallback=arrow(main,'onVehicleHit:',2_000_000),shotCallback=arrow(main,'onShot:',2_000_000);
const hurtStart=vehicle.indexOf('hurt(e){'),hurtEnd=vehicle.indexOf('},burst(',hurtStart)+1;assert(hurtStart>=0&&hurtEnd>hurtStart);
const hurt=vehicle.slice(hurtStart,hurtEnd),shrugStart=vehicle.indexOf('shrugsOff:')+'shrugsOff:'.length,shrugEnd=vehicle.indexOf(',kick(',shrugStart);assert(shrugStart>0&&shrugEnd>shrugStart);
const shrug=vehicle.slice(shrugStart,shrugEnd);
const dispatchStart=main.indexOf('lU=e=>{',1_910_000)+'lU='.length,dispatchEnd=main.indexOf(',lW=new Set',dispatchStart);assert(dispatchStart>0&&dispatchEnd>dispatchStart);
const dispatcher=main.slice(dispatchStart,dispatchEnd);
const context={calls:[],d:{id:400},ey:true,lT:true,es:new Set([432]),tk:new Map(),rP:{yv:0},jK:()=>null,
 tM:false,t7:false,le:0,lt:null,clearTimeout:()=>{},setTimeout:()=>0,performance:{now:()=>5000}};
context.eI={inflict:d=>context.calls.push(['damage',d])};context.pD=w=>{if(Number.isInteger(w))context.calls.push(['wheel',w])};
context.cj={shrugsOff:vm.runInNewContext('('+shrug+')',context),hurt:vm.runInNewContext('({'+hurt+'}).hurt',context)};
context.w=vm.runInNewContext('('+shotCallback+')',context);const normalizeHit=vm.runInNewContext('('+hitAdapter+')',context),vhit=vm.runInNewContext('('+vehicleCallback+')',context);
const cases=[];
const damages=[-100,-1,0,.125,1,17.5,100,1000];
for(const type of ['hit','vhit'])for(const model of [400,432,468,520])for(const driving of [false,true])for(const damage of damages)for(const weapon of [null,0,9,15,16,22,37,46,54,99])for(const wheel of [null,0,1,3]){
 const message={t:type,d:damage,car:true};if(weapon!==null)message.w=weapon;if(wheel!==null)message.wh=wheel;
 context.calls=[];context.d.id=model;context.lT=driving;
 if(type==='hit')normalizeHit(message);else vhit({damage,weapon:message.w,wheel:message.wh});
 cases.push({message,model,driving,expected:context.calls});
}
const commandCases=[];
context.tk=new Map();context.lo=()=>{};
for(const [key,kind]of[['J','fix'],['Q','flip'],['X','slap'],['ee','dress'],['U','tp'],['G','cash'],['e6','passive'],['e8','shield'],['eq','style'],['eT','profile'],['eC','name'],['eW','dose']])context[key]=(...args)=>context.calls.push([kind,...args]);
const dispatch=vm.runInNewContext('('+dispatcher+')',context);
for(const message of [
 {t:'fix'},{t:'flip'},...[.01,1,99,101,1000,0,-1,'3',true].map(h=>({t:'slap',h})),
 ...[0,7,287,-1,1.5,'7',true].map(skin=>({t:'dress',skin,say:'hello'})),
 ...[0,1,-1,.5,1e9,'1',false].map(cash=>({t:'cash',cash})),
 {t:'tp',x:1,y:-2,z:3,g:1,h:Math.PI,out:[4,5]},{t:'tp',x:1,y:-2,z:3,g:true,h:0,out:[4,5]},
 {t:'tp',x:'1',y:2,z:3},{t:'tp',x:1,y:2,z:3,out:[1]},{t:'tp',x:1,y:2,z:3,h:'3'},
 ...[0,1,1.5,-1,-1.5,60,100,'5',false].map(s=>({t:'shield',s})),
 ...[false,true,0,1,'true'].flatMap(on=>[0,1.5,-1,4.5,'3'].map(w=>({t:'passive',on,w}))),
 ...[0,1,2,-1,1.5,'3',true].map(style=>({t:'style',style})),
 {t:'profile',name:'name'},{t:'name',name:'next',done:false},
 ...[0,1,.5,-2,'4'].map(heal=>({t:'dose',heal}))
]){
 context.calls=[];dispatch(message);commandCases.push({message,expected:context.calls});
}
const teleportSource=arrow(main,'onTeleport:',2_000_000),teleportCases=[];
class Vector {constructor(x,y,z){this.x=x;this.y=y;this.z=z;}}
Object.assign(context,{ea:false,l_:true,lA:true,lT:false,c6:{dead:false},ub:{on:false},d:{Pq0:Vector},aS:()=>.5,tN:{},lz:true,dj:()=>false,me:{cameFrom(){}},fc(){},fr(placement){context.placement=placement}});
const teleport=vm.runInNewContext('('+teleportSource+')',context);
for(const heading of [null,0,90,180,-180,360,.5,Math.PI]){
 const message={t:'tp',x:1,y:-2,z:3};if(heading!==null)message.h=heading;
 const decoded=commandCases.length;context.calls=[];context.U=value=>{teleport(value)};dispatch(message);
 const placed=context.placement;assert(placed);
 teleportCases.push({message,point:[placed.feet.x,-placed.feet.z,placed.feet.y],nativeHeading:-placed.heading});
}
const output={sourceSHA256:crypto.createHash('sha256').update(main).digest('hex'),vehicleSHA256:crypto.createHash('sha256').update(vehicle).digest('hex'),expressionSHA256:crypto.createHash('sha256').update([hitAdapter,vehicleCallback,shotCallback,hurt,shrug,dispatcher,teleportSource].join('\n')).digest('hex'),cases,commandCases,teleportCases};
fs.mkdirSync(path.dirname(process.argv[2]),{recursive:true});fs.writeFileSync(process.argv[2],JSON.stringify(output)+'\n',{mode:0o600});
console.log('Recorded actual archived command/vehicle callbacks:',cases.length,'vehicle cases and',commandCases.length,'command cases');
