#!/usr/bin/env node
'use strict';
// Execute the owner's archived arsenal, carried-state synchronizer and staff
// callback offline. Only the numeric observations are written to local-only.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=require('node:path').resolve(__dirname, '../..'),F=require('../vehicles/smoke_vehicle_dynamics').archivedModules()(60662),folder=path.join(root,'local-only/site/_next/static/chunks');
const source=fs.readFileSync(path.join(folder,fs.readdirSync(folder).find(x=>x.startsWith('9737.'))),'utf8');
function extract(start,end,skip){const a=source.indexOf(start),b=source.indexOf(end,a)+1;assert(a>=0&&b>a);return source.slice(a+skip,b)}
const arsenalExpr=extract('tx=function(){let e=Array(F._f).fill(null)','}(),tv=',3);
const syncExpr=extract('pU=function(e){let{carried:t,rearm:l,send:n}=e','}({carried:',3);
const staffExpr=extract('onStaff:e=>{','},onSlap:',8);
const catalog=[];for(let id=0;id<=46;id++){const v=F.U1(id);if(v)catalog.push({id:v.id,slot:v.slot,capacity:v.clip,kind:v.kind,wait:v.pace?.wait??0,reload:v.pace?.reload??0})}
const baseline=[[22,20],[31,80]],hash=s=>crypto.createHash('sha256').update(s).digest('hex');
function world(){let now=0,alive=true;const sent=[],arsenal=vm.runInNewContext('('+arsenalExpr+')()',{F,Math});
 const actor={weapons:()=>arsenal.list(),give:(id,n)=>alive&&(id!==39||arsenal.give(40,1))&&arsenal.give(id,n),putDown:id=>{arsenal.drop(id);if(id===39)arsenal.drop(40)},rearm:rows=>{arsenal.clear();for(const[id,n]of rows)arsenal.give(id,n);arsenal.holster()}};
 const sync=vm.runInNewContext('('+syncExpr+')',{performance:{now:()=>now},Math,Number,Array})({carried:()=>arsenal.list(),rearm:actor.rearm,send:rows=>{sent.push(rows);return true}});
 const staff=vm.runInNewContext('('+staffExpr+')',{ea:false,F,c6:actor,pU:sync,Number,Array,lA:false,lT:false});
 sync.heard(baseline,false);
 return {run(op){alive=op.alive!==false;if(op.type==='staff')staff(op.packet);else if(op.type==='guns')sync.heard(op.rows,op.back);else if(op.type==='revive')sync.revived();else throw Error(op.type)},
  state(flush){if(flush)sync.flush();return {selected:arsenal.weapon,rounds:arsenal.ammo?.clip??0,reserve:arsenal.ammo?.rest??0,ids:arsenal.list().map(x=>x.id).sort((a,b)=>a-b),wire:sent.splice(0)}}};
}
const focused=[
 {give:[39,2]},{take:39},{take:39,back:[24,8]},
 {fill:[24,9]},{fill:[22,80]},{fill:[22,10]},
 {arm:[[39,2]]},{give:[39,1],take:39,back:[22,10],fill:[22,80]},
 {give:[39,1],arm:[[31,7]],disarm:1},{give:[22,2],disarm:0},{disarm:[]},
 {give:[22,5],fill:[31,150],arm:[[24,7.6],[true,8],[31,"20"],[31,0.4],[999,1]]},
 {give:[24,1],take:24,back:[22,3],fill:[31,40],arm:[[39,3]],disarm:""},
 {give:[22,1],take:39,back:[24,7],fill:[22,999]},
 {give:[39,2],take:22,back:[24,8],fill:[31,99],arm:[[22,6],[39,2]]}
].map(packet=>({type:'staff',packet}));
focused.push({type:'staff',alive:false,packet:{give:[39,4],take:39,back:[24,8],fill:[31,500]}});
focused.push({type:'staff',alive:false,packet:{arm:[[24,3.6]],disarm:false}});
focused.push({type:'guns',rows:[[31,12]],back:true},{type:'staff',packet:{arm:[[22,9]]}},{type:'revive'});
let seed=12980721;const random=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n};
const ids=[0,1,4,16,22,24,25,31,39,40,43,44,46,99],pair=()=>[ids[random(ids.length)],random(11000)-30];
function operation(){const kind=random(12),alive=random(7)!==0;
 if(kind===0)return {type:'guns',rows:[pair(),pair()],back:!!random(2)};
 if(kind===1)return {type:'revive'};
 const packet={t:'staff'};
 if(kind===2||kind>=8)packet.give=pair();
 if(kind===3||kind>=8){packet.take=ids[random(ids.length)];packet.back=pair()}
 if(kind===4||kind>=9)packet.fill=pair();
 if(kind===5||kind===10)packet.arm=[pair(),pair(),[39,random(4)+0.6]];
 if(kind===6||kind===11)packet.disarm=[true,false,0,1,'',[]][random(6)];
 if(kind===7){packet.give=[true,8];packet.fill=['22',100];packet.arm=[[22,3.6],['31',20],[false,1],[24,'6']]}
 return {type:'staff',packet,alive};
}
const immediate=world(),operations=[];for(const op of [...focused,...Array.from({length:900},operation)]){immediate.run(op);operations.push({operation:op,state:immediate.state(true)})}
const batches=[];for(let batch=0;batch<36;batch++){const w=world(),ops=Array.from({length:24},operation);for(const op of ops)w.run(op);batches.push({operations:ops,state:w.state(true)})}
const output={sourceSHA256:hash(source),arsenalExpressionSHA256:hash(arsenalExpr),synchronizerExpressionSHA256:hash(syncExpr),staffExpressionSHA256:hash(staffExpr),catalog,baseline,operations,batches};
fs.writeFileSync(process.argv[2],JSON.stringify(output)+'\n',{mode:0o600});console.log('Recorded',operations.length,'actual archived staff/arsenal operations and',batches.length,'deferred-metadata batches');
