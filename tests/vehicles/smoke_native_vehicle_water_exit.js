#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const directory=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/_next/static/chunks');
const source=fs.readFileSync(path.join(directory,fs.readdirSync(directory).find(n=>n.startsWith('2540.'))),'utf8');
const a=source.indexOf('get water(){'),b=source.indexOf(',get wash()',a);assert(a>=0&&b>a);
const method=source.slice(a,b),physics=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/vehicles.physics.json'))).models;
const rows=[];
for(const [id,profile]of Object.entries(physics))for(const shift of [-2,-1e-5,-1e-8,0,1e-8,1e-5,2])
 for(const mode of ['none','dry','fallback','buoyant','sunk']){
  const y=Math.fround(-profile.origin-.4+shift),level=mode==='dry'?null:0,
   context={c:mode==='none'?null:{afloat:mode==='buoyant'||mode==='sunk'?{lost:mode==='sunk',onWater:true}:null},o:{waterLevel:()=>level},d:{origin:profile.origin,boat:profile.kind==='boat'},et:{x:1,y,z:2}};
  const actor=vm.runInNewContext('({'+method+'})',context);rows.push({id,origin:profile.origin,y,level,mode,expected:actor.water==='lost'});
 }
fs.writeFileSync(process.argv[2],JSON.stringify({sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),rows})+'\n',{mode:0o600});
console.log('Recorded actual vehicle water getter:',rows.length,'decisions');
