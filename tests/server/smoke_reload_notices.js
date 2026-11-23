#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual action/note methods and inventory owner. Authored catalog and inert
// storage/network boundaries; no listener, original assets or account files.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=process.argv[2]?path.resolve(process.argv[2]):path.resolve(__dirname,'../..');
const file=path.join(root,'selfhost_backend.js'),source=fs.readFileSync(file,'utf8');
const digest=value=>crypto.createHash('sha256').update(value).digest('hex');
const before=digest(source);
const actionStart=source.indexOf('  action(player, action, input) {');
const actionEnd=source.indexOf('\n  async join(',actionStart);
const noteStart=source.indexOf('  note(player, text) {');
const noteEnd=source.indexOf('\n  owned(',noteStart);
assert(actionStart>0&&actionEnd>actionStart&&noteStart>0&&noteEnd>noteStart);
const inventory=require(path.join(root,'weapon_inventory.js')).create({
 items:[{id:25,name:'Authored shotgun',ammo:5,capacity:1,price:20,slot:3,fire:'INSTANT_HIT'}],shops:[]
},{timingDefinitions:[]});
const Type=vm.runInNewContext('class ActionOwner {\n'+source.slice(actionStart,actionEnd)+'\n'+source.slice(noteStart,noteEnd)+'\n}\nActionOwner;',{weaponInventory:inventory});
let checks=0;const check=(value,label)=>{assert(value,label);checks++;};
const player={health:100,cash:1000,inventory:{revision:1,selected:25,weapons:{25:{clip:0,rest:4}},reload:null}};
function peer(owner,ready=true,inventoryEnabled=true){return{player:owner,ready,inventoryEnabled,sent:[],send(packet){this.sent.push(structuredClone(packet));}};}
const first=peer(player),second=peer(player),unready=peer(player,false),other=peer({health:100});
const game=Object.create(Type.prototype);let saved=0,updates=0;
Object.assign(game,{peers:new Set([first,second,unready,other]),
 position(){return{x:0,y:0,z:0,peer:{state:{walking:true}}};},expireRace(){},
 save(){saved++;},updatePlayer(){updates++;},
 sendInventory(peer,state){peer.send({t:'inventory',state:structuredClone(state)});},
 gameplayState(player){return{weaponInventory:inventory.state(player)};}});
const result=game.action(player,'weapon.reload',{});
check(result.ok===true&&result.message==='Reloading Authored shotgun.','HTTP reply retains its action result');
check(result.state.weaponInventory.reload?.weapon===25,'Actual reload state is owned by inventory');
check(first.sent.filter(p=>p.t==='inventory').length===1&&second.sent.filter(p=>p.t==='inventory').length===1,'Both current ready inventory peers receive the state');
check(unready.sent.length===0&&other.sent.length===0,'No other account or unready connection receives updates');
const stale=[first,second].flatMap(p=>p.sent.filter(x=>x.t==='note'&&x.text===result.message));
assert.throws(()=>game.action(player,'weapon.reload',{}),/already reloading/);checks++;
const noteCounts=[first,second].map(p=>p.sent.filter(x=>x.t==='note').length);
inventory.tick(player,Date.now()+1500);
const complete=inventory.state(player);
check(complete.reload===null&&complete.weapons.some(w=>w.id===25&&w.clip===1&&w.rest===3),'Real inventory completes one shell from reserve');
const selected=game.action(player,'weapon.select',{weapon:0});
check(selected.ok&&selected.message==='Fists selected.','Durable action result is retained');
for(const [i,p]of[first,second].entries()){
 check(p.sent.filter(x=>x.t==='note').length===noteCounts[i]+1&&p.sent.at(-1).text==='Fists selected.','Ordinary per-account notices are still delivered');
}
assert.throws(()=>game.action(player,'weapon.reload',{}),/Select a loaded weapon/);checks++;
check(saved===2&&updates===2,'Rejected actions did not mutate storage/publication ownership');
check(digest(fs.readFileSync(file))===before,'Actual server source unchanged by test');
console.log(JSON.stringify({status:stale.length?'ACTUAL_STALE_RELOAD_PROGRESS_NOTE':'PASS',checks,staleNotes:stale.length,
 scope:'Actual server action/note and inventory methods; authored catalog, inert persistence/socket publication. No App or original-engine claim.'}));
process.exitCode=stale.length?42:0;
