#!/usr/bin/env node
'use strict';
const http=require('node:http'),path=require('node:path'),fs=require('node:fs'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));clearInterval(game.tick);clearInterval(game.projectileTimer);
let checks=0,child,requests=0,complete=false,stopping=false;const sockets=new Set(),original=game.onMessage.bind(game);
function check(ok,text){checks++;if(!ok)throw Error(text)}
function stop(){if(stopping)return;stopping=true;server.close();for(const s of sockets)s.destroy();game.flushSync()}
function fail(e){console.error(e);process.exitCode=1;child?.kill();stop()}
const server=http.createServer((req,res)=>Promise.resolve(game.http(req,res)).catch(fail));
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.once('close',()=>sockets.delete(socket));game.upgrade(req,socket,head)});
game.onMessage=(peer,message)=>{try{
 if(message.t==='hi'&&message.nativeInventory===true)peer.player.armour=25;
 original(peer,message);
 if(message.t==='selfHealth'){
  requests++;const expected=[[100,5,'impact',20],[90,5,'hurt',10],[75,0,'impact',20],[0,0,'impact',200]][requests-1];
  check(expected&&message.kind===expected[2]&&message.damage===expected[3],'Wrong ordered crash/fall request');
  check(peer.player.health===expected[0]&&peer.player.armour===expected[1],'Authority disagreed with predicted armour/health');
  const deaths=peer.player.deaths;original(peer,message);check(peer.player.deaths===deaths,'Duplicate request repeated a death');
  if(requests===3)peer.send({t:'note',text:'MIXED IMPACT ACK'});
  if(requests===4){check(peer.player.deaths===1,'Fatal crash death count');peer.send({t:'note',text:'FATAL IMPACT ACK'})}
 }
}catch(e){fail(e)}};
server.listen(0,'127.0.0.1',()=>{
 child=spawn(process.argv[3],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});child.on('error',fail);child.on('exit',code=>{if(stopping)return;try{
  check(code===0&&requests===4,'Mixed impact client incomplete');complete=true;fs.writeFileSync(process.argv[4],JSON.stringify({status:'PASS',checks,requests},null,2)+'\n');
  console.log(`PASS actual armour impact authority: ${checks} checks; mixed ordered crash/fall, duplicate requests and one fatal death`);
 }catch(e){fail(e)}finally{stop()}});
});
setTimeout(()=>{if(!complete&&!stopping)fail(Error('Impact backend timed out'))},25000).unref();
