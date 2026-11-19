#!/usr/bin/env node
'use strict';
const http=require('node:http'),path=require('node:path'),fs=require('node:fs'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));clearInterval(game.tick);clearInterval(game.projectileTimer);
const cases=[{body:.7,foot:1.9},{body:-3.13,foot:3.13},{body:3.13,foot:-3.13},{body:0,foot:Math.PI/2},{body:2.8,foot:-2.4},{body:.4},{body:-.8},{body:1.1},{body:-1.1}];
let checks=0,native,observer,child,index=0,phase='initial',complete=false,stopping=false,exits=0;const sockets=new Set(),original=game.onMessage.bind(game);
function check(value,text){checks++;if(!value)throw Error(text)}
function close(){if(stopping)return;stopping=true;observer?.close();server.close();for(const s of sockets)s.destroy();game.flushSync()}
function fail(error){console.error(error);process.exitCode=1;child?.kill();close()}
function angle(value,expected,tolerance=1e-6){return Number.isFinite(value)&&Math.abs(value-expected)<tolerance}
const server=http.createServer((req,res)=>Promise.resolve(game.http(req,res)).catch(fail));
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.once('close',()=>sockets.delete(socket));game.upgrade(req,socket,head)});
game.onMessage=(peer,message)=>{try{
 if(message.t==='hi'&&message.nativeInventory===true){native=peer;peer.player.armour=25;
  peer.player.garage[0]={position:[1570,-2460,13.6,0],health:1000,damage:'',work:0};
  game.vehicles.set('fixture-heading',{id:'fixture-heading',owner:peer.player,slot:0,lastGarageSave:0,row:['fixture-heading','Heading fixture','420.0.0.0.',1570,-2460,13.6,0,0,0,1000,'',null,null,null,null,null,0]});
 }
 original(peer,message);if(peer!==native)return;
 if(message.t==='me'&&message.driving===true){
  check(phase==='initial'||phase==='drive','Unexpected repeated drive');
  const car=game.vehicles.get('fixture-heading');
  check(game.vehicleClaim(car)?.peer===peer && game.vehicleClaim(car).driving &&
   peer.state.driving===true && peer.state.vehicle===car.id && car.row[11]===String(peer.player.number),
   'Heading fixture bypassed actual accepted driver authority');
  phase='exit';native.send({t:'note',text:'EXIT HEADING '+index})
 }
 if(message.t==='me'&&message.walking===true&&message.parked){
  check(phase==='exit','Repeated/out-of-order exit');const item=cases[index],body=Math.fround(item.body),foot=Math.fround(item.foot??item.body);exits++;
  check(angle(message.heading,-foot),'First foot packet used parked body/camera heading');
  check(angle(message.parked.heading,-body),'Foot heading replaced parked body yaw');
  check(angle(message.parked.pitch,Math.fround(.15))&&angle(message.parked.roll,-Math.fround(-.2)),'Body pitch/roll changed');
  check(angle(game.vehicles.get('fixture-heading').row[6],-body,.0011),'Authority parked body yaw mismatch');
  check(peer.player.health===100&&peer.player.armour===25,'Orientation handoff changed health/armour');
  phase='observe';observer.send(JSON.stringify({t:'hi'}));
 }
}catch(e){fail(e)}};
server.listen(0,'127.0.0.1',()=>{
 const base='http://127.0.0.1:'+server.address().port;observer=new WebSocket(base.replace('http:','ws:')+'/api/world/live');
 observer.addEventListener('error',e=>{if(!stopping)fail(e.error||Error('Legacy observer error'))});
 observer.addEventListener('open',()=>observer.send(JSON.stringify({t:'hi'})));
 observer.addEventListener('message',event=>{try{
  const p=JSON.parse(event.data);if(p.t!=='all')return;
  if(!child){child=spawn(process.argv[3],[base],{stdio:'inherit'});child.on('error',fail);child.on('exit',code=>{if(stopping)return;try{
   check(code===0&&phase==='complete'&&exits===cases.length,'Native heading transport did not finish');complete=true;
   fs.writeFileSync(process.argv[4],JSON.stringify({status:'PASS',checks,cases:cases.length,exits},null,2)+'\n');
   console.log(`PASS native/legacy first-exit heading transport: ${checks} checks; ${exits} actor/body yaw handoffs, first observer row correct`);
  }catch(e){fail(e)}finally{close()}});return}
  if(phase!=='observe')return;
  const row=p.cars.find(r=>String(r[0])===String(native.player.number)),item=cases[index];
  check(row?.[2]==='s7','Legacy did not observe pedestrian on the first exit row');
  check(angle(row[6],-Math.fround(item.foot??item.body),.0011),'Legacy first-foot facing mismatch');
  check(angle(row[33]?.[4],-Math.fround(item.body),.0011),'Legacy parked body facing mismatch');
  check(row[18]===100&&row[30]===25,'Legacy lost occupant vitals');
  if(++index===cases.length){phase='complete';native.send({t:'note',text:'EXIT HEADINGS COMPLETE'})}
  else {phase='drive';native.send({t:'note',text:'NEXT HEADING '+index})}
 }catch(e){fail(e)}});
});
setTimeout(()=>{if(!complete&&!stopping)fail(Error('Heading backend timed out: '+phase+' case'+index))},30000).unref();
