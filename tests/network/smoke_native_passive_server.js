#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));
const sockets=new Set(),actions=[],original=game.onMessage.bind(game);
let observer,observerPeer,nativePeer,child,stopping=false,complete=false;
function stop(){
  if(stopping)return;stopping=true;observer?.close();
  for(const socket of sockets)socket.destroy();
  server.close();clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();
}
function fail(error){console.error(error);process.exitCode=1;child?.kill();stop();}
const server=http.createServer((req,res)=>{
  try{
    if(req.url.startsWith('/fixture/protection/')){
      const mode=req.url.slice('/fixture/protection/'.length);
      assert(observerPeer&&nativePeer&&((actions.length===0&&mode==='on')||(actions.length===1&&mode==='off')));
      game.action(observerPeer.player,'safety.passive',{});
      assert.equal(observerPeer.player.passive,mode==='on');
      assert.equal(game.row(observerPeer)[48],mode==='on'?1:0);
      actions.push(mode);res.writeHead(200);res.end('ok');return;
    }
    Promise.resolve(game.http(req,res)).catch(fail);
  }catch(error){res.writeHead(500);res.end('fixture failed');fail(error);}
});
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));game.upgrade(req,socket,head);});
game.onMessage=(peer,message)=>{
  try{
    original(peer,message);
    if(message.t==='hi'){
      console.log('PASSIVE_WIRE_HI',peer.player.number,message.nativeInventory,game.fullState(peer).cars.map(r=>[r[0],r[48]]));
      if(message.nativeInventory===true)nativePeer=peer;
      else observerPeer=peer;
    }
    if(peer===observerPeer&&message.t==='me'&&message.walking===true&&!child){
      assert.equal(game.row(peer)[48],0);
      child=spawn(process.argv[3],['http://127.0.0.1:'+server.address().port,String(peer.player.number)],{stdio:'inherit'});
      child.on('error',fail);child.on('exit',code=>{
        if(stopping)return;
        try{assert.equal(code,0);assert.deepEqual(actions,['on','off']);complete=true;
          console.log('PASS actual browser-style peer/server actions/native HTTP+WS passive round trip');
        }catch(error){fail(error);}finally{stop();}
      });
    }
  }catch(error){fail(error);}
};
server.listen(0,'127.0.0.1',()=>{
  observer=new WebSocket('ws://127.0.0.1:'+server.address().port+'/api/world/live');
  observer.addEventListener('error',e=>{if(!stopping)fail(e.error||Error('Observer socket failed'));});
  observer.addEventListener('open',()=>observer.send(JSON.stringify({t:'hi'})));
  observer.addEventListener('message',event=>{
    try{if(JSON.parse(event.data).t==='all'&&!child)observer.send(JSON.stringify({t:'me',walking:true,skin:7,x:10,y:20,z:30,heading:0,weapon:0}));}
    catch(error){fail(error);}
  });
});
setTimeout(()=>{if(!complete&&!stopping)fail(Error('Passive wire timeout'));},45000).unref();
