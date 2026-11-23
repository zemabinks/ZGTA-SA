#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual row method and numeric helpers; authored peer/state, no constructor,
// filesystem writes, listener, timers, resources or gameplay authority.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const file=path.resolve(__dirname,'../../selfhost_backend.js');
const source=fs.readFileSync(file,'utf8');
function block(marker){
  const start=source.indexOf(marker);assert(start>=0,marker);
  let end=source.indexOf('{',start)+1,depth=1;
  while(depth){depth+=(source[end]==='{')-(source[end]==='}');end++;}
  return source.slice(start,end);
}
const helpers=['finite','limited','rounded'].map(n=>block('function '+n+'(')).join('\n');
const Type=vm.runInNewContext(helpers+'\nclass Rows {\n'+block('  row(peer) {')+'\n'+block('  passengerClaim(peer) {')+'\n}\nRows;');
const game=Object.create(Type.prototype);
Object.assign(game,{passengerClaims:new Map(),parkedVehicleReports:new WeakMap(),vehicles:new Map()});
let checks=0;
for(const value of [false,true,0,1,'true','1',null,undefined]){
  const player={number:42,name:'Authored actor',health:73,armour:11,passive:value};
  const peer={player,state:{walking:true,skin:7,x:10,y:20,z:30,heading:.7,clock:1000},lastSeen:Date.now()};
  const before=structuredClone(peer),row=game.row(peer);
  assert(row&&row[0]==='42'&&row[2]==='s7');checks++;
  assert.equal(row[48],value===true?1:0,'Shared row lost authoritative passive admission');checks++;
  assert.equal(row[18],73);assert.equal(row[30],11);checks+=2;
  assert.deepEqual(Array.from(row.slice(3,6)),[10,20,30]);checks++;
  assert.deepEqual(peer,before,'Publication changed player or movement authority');checks++;
}
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),crypto.createHash('sha256').update(source).digest('hex'));
console.log(`PASS ${checks} actual passive row/authority checks; authored peer boundary, no socket/App/retail claim`);
