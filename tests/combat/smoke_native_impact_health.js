#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const load=require('../vehicles/smoke_vehicle_dynamics').archivedModules(),folder=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/_next/static/chunks');
const source=fs.readFileSync(path.join(folder,fs.readdirSync(folder).find(n=>n.startsWith('9737.'))),'utf8');
const a=source.indexOf('hurt(e){',source.indexOf('c6=function(e)')),b=source.indexOf('{',a);let depth=0,quote=null,escape=false,end;
for(let i=b;i<source.length;i++){
 const c=source[i];if(quote){if(escape)escape=false;else if(c==='\\')escape=true;else if(c===quote)quote=null;continue}
 if(['"',"'",'`'].includes(c)){quote=c;continue}if(c==='{')depth++;else if(c==='}'&&!--depth){end=i+1;break}
}assert(a>=0&&end>a);const hurt=source.slice(a,end),cases=[];
for(const health of [1,25,50,100])for(const armour of [0,25,100])for(const amount of [1,5,25,99,100,125,200])
 for(const pattern of ['iii','ifi','fif']){
  const context={e4:false,e1:-1,e0:armour,eZ:health,eb:false,T:null,C:null,td:{on:false},rw:load(19863),nN:load(49368),r7:new Map(),
   ay:()=> 'koFront',lr(){context.eZ=0;context.e1=0}};
  vm.createContext(context);const actor=vm.runInContext('({'+hurt+'})',context),rows=[];
  for(const kind of pattern){const damage=kind==='f'?Math.min(10,amount):amount;
   actor.hurt(damage,{quiet:true,...(kind==='f'?{weapon:54}:{})});
   rows.push({kind:kind==='f'?'hurt':'impact',damage,health:context.eZ,armour:context.e0});
  }
  cases.push({health,armour,rows});
 }
fs.writeFileSync(process.argv[2],JSON.stringify({sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),cases})+'\n',{mode:0o600});
console.log('Recorded actual quiet crash/fall damage:',cases.length,'ordered scenarios');
