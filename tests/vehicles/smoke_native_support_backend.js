#!/usr/bin/env node
'use strict';
// Native URLSession -> unchanged self-host authority -> legacy browser-shaped
// rows. Catalogs contain synthetic data only; no original assets are needed.
const http=require('node:http'),path=require('node:path'),fs=require('node:fs'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));
clearInterval(game.tick);clearInterval(game.projectileTimer);
let checks=0,child,observer,native,stage=0,complete=false,stopping=false;
const sockets=new Set(),original=game.onMessage.bind(game),expected=['platform-fixture',.13,-.24,1.01];
function check(ok,message){checks++;if(!ok)throw Error(message)}
function equal(a,b,message){check(JSON.stringify(a)===JSON.stringify(b),message+': '+JSON.stringify(a))}
function stop(){if(stopping)return;stopping=true;observer?.close();server.close();for(const socket of sockets)socket.destroy();game.flushSync()}
function fail(error){console.error(error);process.exitCode=1;child?.kill();stop()}
const server=http.createServer((req,res)=>Promise.resolve(game.http(req,res)).catch(fail));
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.once('close',()=>sockets.delete(socket));game.upgrade(req,socket,head)});
game.onMessage=(peer,message)=>{
 try{
  original(peer,message);
  if(message.t==='hi'&&message.nativeInventory===true){native=peer;check(peer.ready,'Native not ready after actual authority handshake')}
  if(peer===native&&message.t==='me'&&message.walking===true){
   check(stage===0||stage===2,'Support packet out of sequence');stage++;
   equal(game.row(peer)[39],stage===1?expected:null,'Authority support row differs');
   observer.send(JSON.stringify({t:'hi'}));
  }
 }catch(error){fail(error)}
};
server.listen(0,'127.0.0.1',()=>{
 const base='http://127.0.0.1:'+server.address().port;
 observer=new WebSocket(base.replace('http:','ws:')+'/api/world/live');
 observer.addEventListener('error',event=>{if(!stopping)fail(event.error||Error('Legacy observer error'))});
 observer.addEventListener('open',()=>observer.send(JSON.stringify({t:'hi'})));
 observer.addEventListener('message',event=>{
  try{
   const message=JSON.parse(event.data);if(message.t!=='all')return;
   if(!child){child=spawn(process.argv[3],[base],{stdio:'inherit'});child.on('error',fail);child.on('exit',code=>{
    if(stopping)return;try{check(code===0&&stage===4,'Native/legacy support fixture did not complete');complete=true;
     fs.writeFileSync(process.argv[4],JSON.stringify({status:'PASS',checks,stage,expected},null,2)+'\n');console.log(`PASS support authority: ${checks} checks; native attach/detach received by legacy observer`);
    }catch(error){fail(error)}finally{stop()}
   });return}
   const row=message.cars.find(row=>String(row[0])===String(native.player.number));check(row!=null,'Legacy observer lost native walking row');
   if(stage===1){equal(row[39],expected,'Legacy support attachment differs');stage=2;native.send({t:'note',text:'SUPPORT ATTACHED'})}
   else if(stage===3){equal(row[39],null,'Legacy retained detached support');stage=4;native.send({t:'note',text:'SUPPORT COMPLETE'})}
  }catch(error){fail(error)}
 });
});
setTimeout(()=>{if(!complete&&!stopping)fail(Error('Support backend fixture timed out at stage '+stage))},25000).unref();
