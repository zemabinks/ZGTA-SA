#!/usr/bin/env node
'use strict';
const http=require('node:http'),path=require('node:path'),fs=require('node:fs'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));clearInterval(game.tick);clearInterval(game.projectileTimer);
let checks=0,child,observer,native,phase=0,requests=0,complete=false,stopping=false,waterObserved=false;const sockets=new Set(),original=game.onMessage.bind(game);
function check(ok,message){checks++;if(!ok)throw Error(message)}
function stop(){if(stopping)return;stopping=true;observer?.close();server.close();for(const socket of sockets)socket.destroy();game.flushSync()}
function fail(error){console.error(error);process.exitCode=1;child?.kill();stop()}
const server=http.createServer((req,res)=>Promise.resolve(game.http(req,res)).catch(fail));
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.once('close',()=>sockets.delete(socket));game.upgrade(req,socket,head)});
game.onMessage=(peer,message)=>{
 try{
  if(message.t==='hi'&&message.nativeInventory===true){
   native=peer;peer.player.armour=25;
   peer.player.garage[0]={position:[1570,-2460,13.6,0],health:1000,damage:'',work:0};
   game.vehicles.set('fixture-wreck',{id:'fixture-wreck',owner:peer.player,slot:0,lastGarageSave:0,
    row:['fixture-wreck','Synthetic owned car','420.0.0.0.',1570,-2460,13.6,0,0,0,1000,'',null,null,null,null,null,0]});
  }
  original(peer,message);
  if(peer!==native)return;
  if(message.t==='selfHealth'){
   requests++;
   if(message.kind==='hurt'){
    check(message.damage===100&&message.s===1,'Wreck did not use one environmental fatal request');
    const deaths=peer.player.deaths;original(peer,message);check(peer.player.deaths===deaths&&deaths===1,'Duplicate fatal request counted another death');
    check(peer.player.health===0&&peer.player.armour===25,'Fatal health owner lost armour or restored health');
   }else{check(message.kind==='respawn'&&message.s===2&&peer.player.health===100,'Respawn acknowledgement failed')}
  }
  if(message.t==='me'&&message.driving===true){check(peer.player.health===100,'Driver started dead');native.send({t:'note',text:waterObserved?'WRECK NOW':'LEAVE SUNKEN VEHICLE'})}
  if(message.t==='me'&&message.walking===true&&message.parked){
   if(!waterObserved){
    check(peer.player.health===100&&peer.player.armour===25,'Water exit manufactured damage');
    check(peer.player.garage[0].health===800,'Water exit lost parked hull state');
    phase=-1;observer.send(JSON.stringify({t:'hi'}));return;
   }
   check(peer.player.health===0&&peer.player.deaths===1,'Exit revived occupant or duplicated death');
   check(game.vehicles.get('fixture-wreck').row[9]===0&&peer.player.garage[0].health===0,'Exit lost authoritative wrecked hull');
   check(message.x===1572&&message.parked.x===1570,'Foot and parked coordinate owners mixed');
   phase=1;observer.send(JSON.stringify({t:'hi'}));
  }else if(message.t==='me'&&message.walking===true&&phase===2){phase=3;observer.send(JSON.stringify({t:'hi'}))}
 }catch(error){fail(error)}
};
server.listen(0,'127.0.0.1',()=>{
 const base='http://127.0.0.1:'+server.address().port;
 observer=new WebSocket(base.replace('http:','ws:')+'/api/world/live');observer.addEventListener('error',e=>{if(!stopping)fail(e.error||Error('Observer error'))});
 observer.addEventListener('open',()=>observer.send(JSON.stringify({t:'hi'})));
 observer.addEventListener('message',event=>{try{
  const packet=JSON.parse(event.data);if(packet.t!=='all')return;
  if(!child){child=spawn(process.argv[3],[base],{stdio:'inherit'});child.on('error',fail);child.on('exit',code=>{if(stopping)return;try{
   check(code===0&&phase===4&&requests===2,'Water/wreck transport did not finish');complete=true;
   fs.writeFileSync(process.argv[4],JSON.stringify({status:'PASS',checks,requests,deaths:native.player.deaths},null,2)+'\n');
   console.log(`PASS native/legacy water/wreck transport: ${checks} checks; one fatal ownership, parked wreck, observed death and acknowledged respawn`);
  }catch(e){fail(e)}finally{stop()}});return}
  const row=packet.cars.find(r=>String(r[0])===String(native.player.number));check(row!=null,'Observer lost occupant');
  if(phase===-1){check(row[2]==='s7'&&row[18]===100&&row[33]?.[7]===800,'Legacy lost living water exit');waterObserved=true;phase=0;native.send({t:'note',text:'REENTER AFTER WATER'});return}
  if(phase===1){check(row[2]==='s7'&&row[18]===0&&row[33]?.[7]===0,'Legacy did not observe dead foot actor and parked wreck');phase=2;
   native.player.lastDeath=Date.now()-3000;native.send({t:'note',text:'RESPAWN AFTER WRECK'});
  }else if(phase===3){check(row[2]==='s7'&&row[18]===100&&row[33]===null,'Respawn retained old driving/exit state');
   check(game.vehicles.get('fixture-wreck').row[9]===0,'Respawn repaired wrecked vehicle');phase=4;native.send({t:'note',text:'WRECK TRANSPORT COMPLETE'});
  }
 }catch(error){fail(error)}});
});
setTimeout(()=>{if(!complete&&!stopping)fail(Error('Wreck backend timed out: phase'+phase))},25000).unref();
