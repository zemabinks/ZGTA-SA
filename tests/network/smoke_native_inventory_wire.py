#!/usr/bin/env python3
"""Actual Swift URLSession WS+HTTP reconciliation with bounded delayed peers."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
let child,finished=false,connections=0,current,revision=0,selected=22,reloading=false,firstGET=true,resyncGET=false,staleGET=null,stalePOST=null,staleReleased=false,heldPosts=0;
const ammo={22:17,28:50},peers=[];
let initialReply=null,initialACKs=new Map(),initialSchedule=false;
function scheduleInitial(){
 if(initialSchedule||!initialReply||initialACKs.size<2)return;initialSchedule=true;
 setTimeout(()=>json(initialReply.res,{weaponInventory:initialReply.state}),100);
 setTimeout(()=>inventory(initialReply.peer,initialACKs.get(1)),250);
 setTimeout(()=>inventory(initialReply.peer,initialACKs.get(2)),450);
}
function releaseStaleWhenHeld(){
 if(!staleGET||!stalePOST||staleReleased)return;staleReleased=true;
 send(current,{t:'note',text:'RESYNC NOW'});
 setTimeout(()=>{json(staleGET.res,{weaponInventory:staleGET.state});json(stalePOST.res,{state:{weaponInventory:stalePOST.state},message:'STALE ACTION MUST NOT COMPLETE'});send(current,{t:'note',text:'STALE HTTP RELEASED'})},300);
}
function state(p){return {revision,selected,weapons:[{id:0,clip:0,rest:0},{id:22,clip:ammo[22],rest:100},{id:28,clip:ammo[28],rest:100}],reload:reloading?{weapon:selected,remainingMs:100}:null,ack:{connection:p.nonce,processedShot:p.ack}}}
function send(p,value){if(p.socket.destroyed)return;const b=Buffer.from(JSON.stringify(value)),h=b.length<126?Buffer.from([129,b.length]):Buffer.from([129,126,b.length>>8,b.length&255]);p.socket.write(Buffer.concat([h,b]))}
function inventory(p,value=state(p)){send(p,{t:'inventory',state:value})}
function json(res,value){res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(value))}
function received(p,m){
 if(m.t==='hi'){
  assert.equal(m.inventoryAck,1);assert.equal(m.nativeInventory,true);
  const hello={t:'hello',inventoryAck:1,inventoryConnection:p.nonce,life:[100,0]};send(p,hello);inventory(p);setTimeout(()=>{p.ready=true;send(p,{t:'all',you:'Inventory peer',cash:0,cars:[],vehicles:[],chat:[]})},30);
  if(connections===1)setTimeout(()=>send(p,hello),100);
  else setTimeout(()=>inventory(p,{...state(p),revision:999,ack:{connection:'wire-A',processedShot:99}}),10);
 }
 if(m.t==='shot'){
  assert(p.ready,'Shot before all/inventory baseline');assert.equal(m.c,p.nonce);assert.equal(m.s,p.ack+1);p.ack=m.s;
  const accepted=!(p.nonce==='wire-A'&&m.s===2);
  if(accepted){ammo[m.w]--;revision++}
  const snapshot=state(p);const delay=p.nonce==='wire-B'?100:m.s===1?240:m.s===2?400:100;
  if(p.nonce==='wire-A'&&m.s===3)resyncGET=true;
  if(p.nonce==='wire-A'&&m.s<=2){initialACKs.set(m.s,snapshot);scheduleInitial()}else setTimeout(()=>inventory(p,snapshot),delay);
 }
}
const server=http.createServer((req,res)=>{
 assert.equal(req.headers['x-zgta-inventory-connection'],current.nonce,'native HTTP missing/current wrong connection header');
 if(req.method==='GET'){
  if(firstGET){firstGET=false;const old={...state(current),revision:0,selected:22,weapons:[{id:22,clip:17,rest:100},{id:28,clip:50,rest:100}],reload:null,ack:{connection:'wire-A',processedShot:0}};initialReply={res,state:old,peer:current};scheduleInitial();return}
  if(resyncGET&&current.nonce==='wire-A'){
   resyncGET=false;staleGET={res,state:state(current)};releaseStaleWhenHeld();return;
  }
  json(res,{weaponInventory:state(current)});return;
 }
 let body='';req.on('data',b=>body+=b);req.on('end',()=>{
  const input=JSON.parse(body);
  if(input.action==='fixture.hold'){heldPosts++;assert.equal(heldPosts,1,'Uncertain old action must not replay');stalePOST={res,state:state(current)};releaseStaleWhenHeld();return}
  if(input.action==='weapon.reload'){
   const before=state(current);inventory(current,before);reloading=true;revision++;
   const result=state(current);setTimeout(()=>json(res,{state:{weaponInventory:result},message:'Reload started'}),60);
   setTimeout(()=>{reloading=false;ammo[22]=17;revision++;inventory(current)},200);
  }else if(input.action==='weapon.select'){
   assert.equal(input.weapon,28);selected=28;revision++;json(res,{state:{weaponInventory:state(current)},message:'Selected'});
  }else throw Error('Unexpected action '+input.action);
 });
});
server.on('upgrade',(req,s)=>{
 const p={socket:s,nonce:++connections===1?'wire-A':'wire-B',ack:0};assert(connections<=2,'resync reconnected more than once');current=p;peers.push(p);
 if(connections===2)revision=0;
 s.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')+'\r\n\r\n');
 let pending=Buffer.alloc(0);s.on('data',chunk=>{
  pending=Buffer.concat([pending,chunk]);while(pending.length>=2){let length=pending[1]&127,start=2;if(length===126){if(pending.length<4)return;length=pending.readUInt16BE(2);start=4}assert(length!==127);const masked=!!(pending[1]&128),mask=masked?pending.subarray(start,start+4):null;if(masked)start+=4;if(pending.length<start+length)return;const opcode=pending[0]&15,payload=Buffer.from(pending.subarray(start,start+length));pending=pending.subarray(start+length);if(masked)for(let i=0;i<length;i++)payload[i]^=mask[i%4];if(opcode===1)received(p,JSON.parse(payload));else if(opcode===8){s.end();return}}
 });s.on('error',()=>{});
});
server.listen(0,'127.0.0.1',()=>{
 child=spawn(process.argv[2],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});
 child.on('exit',code=>{assert.equal(code,0);assert.equal(connections,2);assert.equal(ammo[22],17);assert.equal(ammo[28],48);assert(staleReleased&&staleGET&&stalePOST);assert.equal(heldPosts,1);finished=true;for(const p of peers)p.socket.destroy();server.close();console.log('PASS real native WS/HTTP inventory: delayed duplicate refresh, firstACK/later pending, rejection, reload, selection, stale GET/action suppression, stale nonce, idempotent reconnect and sequence restart')});
});
setTimeout(()=>{if(!finished){child?.kill();for(const p of peers)p.socket.destroy();server.close();throw Error('Inventory wire timed out')}},20000).unref();
'''
SWIFT=r'''
let address=ServerAddress(CommandLine.arguments[1])!,client=NativeMultiplayerClient(server:address),http=NativeGameplayClient(server:address),heldHTTP=NativeGameplayClient(server:address)
let gun=NativeWeaponState.Weapon(id:22,name:"Pistol",model:"",range:40,capacity:17,interval:0.3,animation:"",fireKind:"INSTANT_HIT")
let smg=NativeWeaponState.Weapon(id:28,name:"SMG",model:"",range:40,capacity:50,interval:0.1,animation:"",fireKind:"INSTANT_HIT")
let weapons=NativeWeaponState(catalog:[gun,smg])
var phase="start",httpDuplicate=false,acceptedFirst=false,rejectedSecond=false,oldHTTPReleased=false,newShot=false,finished=false,settling=false
var httpStates=0,httpResults=0,heldStates=0,heldResults=0,heldCompletions=0
var connections:[String]=[],oldTicket:NativeShotTicket?
func shot(_ weapon:Int)->NativeShotTicket {
 let ticket=client.reserveShot()!
 precondition(NativeWeaponShotDelivery.deliver(weapon:weapon,left:false,ticket:ticket,inventory:weapons,readiness:{_ in},emission:{w,_,t in
  precondition(client.sendWeaponShot(weapon:w,from:SIMD3(0,0,1),to:SIMD3(0,10,1),player:nil,ticket:t))
 }))
 return ticket
}
func finishIfReady(){
 guard oldHTTPReleased,newShot,!settling else{return};settling=true
 let counts=[httpStates,httpResults,heldStates,heldResults,heldCompletions]
 DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
  precondition([httpStates,httpResults,heldStates,heldResults,heldCompletions]==counts,"Old-peer HTTP delivered a stale state/result/completion")
  precondition(heldStates==0 && heldResults==0 && heldCompletions==0,"Held action escaped connection barrier")
  precondition(weapons.selected==28 && weapons.rounds==48 && weapons.pendingShotCount==0)
  finished=true;client.disconnect()
 }
}
func startSwitchIfReady(){
 guard phase=="reloading",weapons.canFire,weapons.rounds==17 else{return}
 phase="switch"
 http.perform("weapon.select",payload:["weapon":28]){result in
  precondition(result==true && weapons.selected==28 && weapons.rounds==50)
  phase="afterSwitch";oldTicket=shot(28)
 }
}
func startReloadIfReady(){
 guard phase=="shoot",httpDuplicate,acceptedFirst,rejectedSecond else{return}
 phase="reloadRequest";let id=weapons.beginReloadRequest();precondition(weapons.reloading && !weapons.canFire)
 http.perform("weapon.reload"){result in
  precondition(result==true);weapons.finishReloadRequest(id:id,succeeded:result);phase="reloading";startSwitchIfReady()
 }
}
func receive(_ inventory:[String:Any],httpResponse:Bool){
 let ack=NativeInventoryAcknowledgement(inventory)!
 let applied=weapons.apply(inventory)
 if ack.connection != client.inventoryConnection{
  preconditionFailure("Old peer HTTP/snapshot leaked past transport generation: \(ack.connection)")
 }
 if phase=="start" && ack.connection=="wire-A"{
  precondition(applied && weapons.canFire && !client.isReady && client.reserveShot()==nil);return
 }
 if phase=="shoot"{
  if httpResponse {precondition(ack.processedShot==0 && weapons.rounds==15 && connections.count==1);httpDuplicate=true}
  if ack.processedShot==1 {precondition(weapons.rounds==15 && weapons.pendingShotCount==1);acceptedFirst=true}
  if ack.processedShot==2 {precondition(weapons.rounds==16 && weapons.pendingShotCount==0);rejectedSecond=true}
  startReloadIfReady();return
 }
 if phase=="reloadRequest"{precondition(weapons.reloading && !weapons.canFire);return}
 if phase=="reloading"{startSwitchIfReady();return}
 if phase=="afterSwitch" && ack.processedShot==3{
  precondition(weapons.rounds==49 && weapons.pendingShotCount==0);phase="captureHTTP";http.refresh()
  heldHTTP.perform("fixture.hold"){_ in heldCompletions += 1;preconditionFailure("Stale old-peer action completion delivered")};return
 }
 if phase=="reconnect" && ack.connection=="wire-B"{
  precondition(applied && ack.processedShot==0 && weapons.selected==28 && weapons.rounds==49)
  precondition(!client.isReady && client.reserveShot()==nil);return
 }
 if phase=="newShot" && ack.connection=="wire-B" && ack.processedShot==1{
  precondition(weapons.rounds==48 && weapons.pendingShotCount==0);newShot=true;finishIfReady()
 }
}
weapons.onNeedsRefresh={http.refresh()};weapons.onNeedsResync={client.requestInventoryResync()}
client.onInventoryConnection={nonce in
 http.inventoryConnection=nonce;heldHTTP.inventoryConnection=nonce;weapons.setConnection(nonce)
 if let nonce{connections.append(nonce);precondition(connections==["wire-A"] || connections==["wire-A","wire-B"])}
}
client.onInventory={receive($0,httpResponse:false)}
client.onConnectionState={state in
 let ready=state == .ready;http.setConnectionReady(ready);heldHTTP.setConnectionReady(ready)
 guard ready else {precondition(client.reserveShot()==nil);return}
 if phase=="start" {
  precondition(weapons.canFire);phase="shoot";http.refresh();_ = shot(22);_ = shot(22)
  precondition(weapons.rounds==15)
 } else if phase=="reconnect" {
  precondition(weapons.selected==28 && weapons.rounds==49)
  precondition(!client.sendWeaponShot(weapon:28,from:.zero,to:SIMD3(0,1,0),player:nil,ticket:oldTicket!))
  phase="newShot";let ticket=shot(28);precondition(ticket.sequence==1)
 }
}
http.onState={httpStates += 1;receive($0["weaponInventory"] as! [String:Any],httpResponse:true)}
http.onResult={_ in httpResults += 1}
heldHTTP.onState={_ in heldStates += 1;preconditionFailure("Old-peer action state delivered")}
heldHTTP.onResult={_ in heldResults += 1;preconditionFailure("Old-peer action result delivered")}
client.onStatus={text in
 if text=="STALE HTTP RELEASED" {oldHTTPReleased=true;finishIfReady()}
 if text=="RESYNC NOW"{precondition(phase=="captureHTTP");phase="reconnect";client.requestInventoryResync();client.requestInventoryResync()}
}
precondition(client.reserveShot()==nil);client.connect()
let deadline=Date().addingTimeInterval(15)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.01));weapons.tick()}
precondition(finished && connections==["wire-A","wire-B"],"native inventory fixture incomplete: \(phase)")
'''
def main():
    output=ROOT/'local-only/native-physics/tests/inventory-wire';output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='run-',dir=output) as directory:
        folder=Path(directory);(folder/'peer.cjs').write_text(JS)
        actor=(ROOT/'ios/App/NativeActorAnimation.swift').read_text()
        actor=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        sources=['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState','NativeWeaponShotDelivery','NativeGameplayClient','NativeShotTargeting','NativeStreamShotClaims','NativeOriginalWorldProtocol','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPLocalVitals','NativeMultiplayerClient']
        source='\n'.join((ROOT/'ios/App'/f'{name}.swift').read_text() for name in sources)+'\n'+actor+'\n'+SWIFT
        (folder/'main.swift').write_text(source)
        subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(output/'modules'),str(folder/'main.swift'),'-o',str(folder/'client')],check=True)
        subprocess.run(['node',str(folder/'peer.cjs'),str(folder/'client')],check=True)
if __name__=='__main__':main()
