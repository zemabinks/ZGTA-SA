#!/usr/bin/env node
'use strict';
// Actual selfhost_backend / Peer / HTTP / WS authority. Only invented model
// catalog + garage/target seeding and deliberate transport loss are fixtures.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));
clearInterval(game.tick);clearInterval(game.projectileTimer); // Unrelated jobs/world timers do not drive this scenario.
let checks=0,child,observer,firstPlayer,firstNonce,root,activeNative,joins=0,observerHellos=0,stage=0,complete=false,stopping=false;
let droppedACKs=0,parkingMarker=false,finalParking=false,observerParkedWork=false,observerFinalWork=false;
const sockets=new Set(),hitches=[],wire=[],releases=[],failures=[];
const original=game.onMessage.bind(game),sequences=new Map();
function check(condition,message){checks++;if(!condition)throw Error(message);}
function equal(actual,expected,message){check(JSON.stringify(actual)===JSON.stringify(expected),`${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);}
function stop(){if(stopping)return;stopping=true;observer?.close();server.close();setTimeout(()=>{for(const socket of sockets)socket.destroy();},250).unref();game.flushSync();}
function fail(error){failures.push(error.stack||String(error));console.error(error);process.exitCode=1;child?.kill();stop();}
function savedWork(expected){game.flushSync();const saved=JSON.parse(fs.readFileSync(path.join(process.argv[2],'local-only/selfhost/players.json')));const player=Object.values(saved.players).find(p=>p.cars.includes(8001));check(player?.garage?.[0]?.work===expected,`Disk save did not retain work ${expected}`);}
function maybeMarkers(){
 const count=id=>releases.filter(value=>value===id).length;
 if(stage===1&&observerParkedWork&&count('a')===1&&count('b')===1&&!parkingMarker){parkingMarker=true;activeNative.send({t:'note',text:'FIXTURE PARKING SEEN'});}
 if(stage===2&&finalParking&&observerFinalWork&&count('a')===3&&count('b')===2){
  stage=3;equal(game.coupling.snapshot().links,[],'Final authoritative topology not released');
  activeNative.send({t:'note',text:'FIXTURE COMPLETE'});
 }
}
const server=http.createServer((req,res)=>{Promise.resolve(game.http(req,res)).catch(fail);});
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));game.upgrade(req,socket,head);});
game.onMessage=(peer,message)=>{
 try{
  if(message.t==='hi'&&message.nativeInventory===true){
   joins++;check(message.inventoryAck===1&&message.couplingAck===1,'Native did not negotiate real capability');activeNative=peer;
   if(joins===1){
    firstPlayer=peer.player;check(game.players.size===2,'HTTP cookie did not reuse native guest (expected native + observer)');
    // Explicit administrator-only synthetic test setup. Real owned factory,
    // later me/vmove/parking authority and save code are unchanged.
    peer.player.cars=[8001];peer.player.garage=[{position:[120,100,20,0],health:1000,damage:'',pitch:0,roll:0,work:0,active:true}];
    root=game.addOwnedVehicle(peer.player,0);check(root?.owner===firstPlayer,'Actual garage factory failed');
    for(const[id,y]of[['a',95],['b',90],['c',85]])game.vehicles.set(id,{id,row:[id,'Synthetic trailer','8002.0',102,y,20,0,0,0,1000,'',null,null,null,null,null,0]});
   }else{
    check(joins===2,'Extra reconnect/uncertain replay');check(peer.player===firstPlayer,'Reconnect replaced actual cookie guest');
    check(firstPlayer.garage[0].work===1876,'Reconnect lost parked garage work');equal(game.coupling.snapshot().links,[],'Disconnect retained authoritative claims');
    stage=2;
   }
   const send=peer.send.bind(peer);peer.send=packet=>{
    wire.push({join:joins,type:packet.t,...(packet.t==='couplings'?{revision:packet.state?.revision,links:packet.state?.links,ack:packet.ack}:{} )});
    if(packet.t==='couplings'&&packet.ack?.sequence===7&&joins===1){check(packet.ack.accepted===true,'Lost ACK was not accepted by authority');droppedACKs++;return;}
    send(packet);
   };
   original(peer,message);
   if(joins===1){firstNonce=peer.inventoryConnection;stage=1;}else check(peer.inventoryConnection!==firstNonce,'Fresh peer reused nonce');
   const sent=wire.filter(item=>item.join===joins);equal(sent.slice(0,3).map(item=>item.type),['hello','couplings','all'],'Actual baseline order changed');
   check(!sent[1].ack&&sent[1].links.length===0,'Baseline invented sequence0 ACK or retained graph');
   return;
  }
  if(message.t==='hi'){observerHellos++;original(peer,message);return;}
  if(peer.inventoryEnabled&&message.t==='hitch'){
   const issued=sequences.get(joins)||[];issued.push(message.s);sequences.set(joins,issued);hitches.push({join:joins,sequence:message.s,parent:message.v,trailer:message.tr});
   check(message.c===peer.inventoryConnection,'Client sent stale hitch nonce');check(message.s===issued.length,'Client sequence gap or replay');
   if(joins===1&&message.s===1){
    check(root.row[3]===100&&root.row[4]===100&&root.row[16]===1234,'Fresh full driver pose/work not applied before hitch');
    check(game.vehicles.get('a').row[3]===100&&game.vehicles.get('b').row[3]===100,'Fresh target vmove was not applied before hitch');
    equal(peer.state.vehicle,root.id,'Fresh driver ownership missing');
   }
   original(peer,message);
   const expected=joins===1?[true,true,false,true,true,true,true][message.s-1]:true;
   check(peer.couplingResults.get(message.s)===expected,`Unexpected actual authority verdict ${joins}/${message.s}`);
   check(peer.processedCouplingSequence===message.s,'Rejected request did not consume exactly one sequence');
   const links=game.coupling.snapshot().links;
   if(joins===1&&message.s===2)check(links.length===2,'Actual two-link topology not installed');
   if(joins===1&&message.s===3)check(links.length===2,'Third-link rejection changed topology');
   if(joins===1&&message.s===4)equal(links,[{parent:root.id,trailer:'a',kind:'trailer'}],'Partial release affected wrong link');
   if(joins===1&&message.s===5)equal(links,[],'Manual root release retained claims');
   if(joins===1&&message.s===7){check(links.length===2&&droppedACKs===1,'Uncertain request not applied before loss');game.flushSync();setImmediate(()=>peer.socket.destroy());}
   return;
  }
  original(peer,message);
  if(peer.inventoryEnabled&&message.t==='me'&&message.walking===true&&message.parked){
   const expected=joins===1?1876:2000;
   check(message.parked.w===expected&&root.row[16]===expected&&firstPlayer.garage[0].work===expected,'Actual parked packet did not update work/garage');
   savedWork(expected);equal(game.coupling.snapshot().links,[],'Parking did not release current driver claims');
   if(joins===2)finalParking=true;
   // The independent legacy peer obtains its normal fullState through a real
   // duplicate legacy hi, rather than directly reading native callback data.
   observer.send(JSON.stringify({t:'hi'}));
  }
 }catch(error){fail(error);}
};
server.listen(0,'127.0.0.1',()=>{
 const base='http://127.0.0.1:'+server.address().port;
 observer=new WebSocket(base.replace('http:','ws:')+'/api/world/live');
 observer.addEventListener('error',event=>{if(!stopping)fail(event.error||Error('Legacy observer socket error'));});
 observer.addEventListener('open',()=>observer.send(JSON.stringify({t:'hi'})));
 observer.addEventListener('message',event=>{
  try{
   const packet=JSON.parse(event.data);check(packet.t!=='couplings','Legacy observer received negotiated native-only graph');
   if(packet.t==='all'){
    if(!child){
     check(observerHellos===1,'Observer initial handshake missing');
     child=spawn(process.argv[3],[base],{stdio:'inherit'});child.on('error',fail);
     child.on('exit',code=>{
      if(stopping)return;
      try{
       check(code===0,'Native process failed');check(stage===3,'Observer did not complete actual final release');
       check(joins===2&&game.players.size===2,'Guest reconnect identity/player count changed');
       equal(sequences.get(1),[1,2,3,4,5,6,7],'First namespace requests differed');equal(sequences.get(2),[1],'New namespace replayed pending request');
       check(droppedACKs===1,'Expected one accepted ACK loss');savedWork(2000);
       check(hitches.length===8&&observerHellos===3,'Unexpected request/observer baseline count');
       complete=true;
       const report={status:'PASS',checks,joins,hitches,droppedACKs,legacyReleases:releases,observerHellos,finalWork:2000,wire};
       fs.writeFileSync(process.argv[4],JSON.stringify(report,null,2)+'\n');
       console.log(`PASS actual selfhost coupling authority: ${checks} checks; 8 real hitch requests; 2 native cookie/nonce sessions; 5 legacy releases; parked work 1876 -> 2000 persisted`);
      }catch(error){fail(error);}finally{stop();}
     });
    }else{
     const row=packet.vehicles.find(row=>row[0]===root.id);check(row!=null,'Legacy fullState lost owned vehicle');
     if(stage===1){check(row[16]===1876,'Legacy row lost first parked work');observerParkedWork=true;}
     else if(stage===2){check(row[16]===2000,'Legacy row lost final parked work');observerFinalWork=true;}
    }
   }
   if(packet.t==='unhitch'){check(['a','b'].includes(packet.v),'Legacy release used parent or unknown vehicle ID');releases.push(packet.v);}
   maybeMarkers();
  }catch(error){fail(error);}
 });
});
const timeout=setTimeout(()=>{if(!complete)fail(Error(`Coupling backend timed out: joins${joins}, stage${stage}, requests${JSON.stringify(hitches)}, releases${JSON.stringify(releases)}`));},60000);timeout.unref();
process.on('uncaughtException',fail);process.on('unhandledRejection',fail);
