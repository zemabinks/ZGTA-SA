#!/usr/bin/env node
'use strict';
// Independently authored fixtures execute actual LocalGame action/correction
// methods in a VM. No backend constructor, listener, save, timer or game data.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const args=process.argv.slice(2),historical=args.includes('--expect-historical-mismatch');
const sourceAt=args.indexOf('--source');
assert(args.every((a,i)=>a==='--expect-historical-mismatch'||a==='--source'||i===sourceAt+1),'Unknown argument');
const file=sourceAt<0?path.join(__dirname,'selfhost_backend.js'):path.resolve(args[sourceAt+1]);
const source=fs.readFileSync(file,'utf8'),nativeFile=path.join(__dirname,'ios/App/NativeMultiplayerClient.swift');
const native=fs.readFileSync(nativeFile,'utf8');
const sha=s=>crypto.createHash('sha256').update(s).digest('hex');
let checks=0;const outcomes=[],mismatches=[];
function check(v,label){checks++;assert(v,label);}
function equal(a,b,label){checks++;assert.deepEqual(JSON.parse(JSON.stringify(a)),b,label);}
const near=(a,b)=>Number.isFinite(a)&&Math.abs(a-b)<1e-10;
const begin=source.indexOf('class LocalGame {'),end=source.indexOf('\nclass Peer {',begin);
check(begin>0&&end>begin,'Actual class extraction markers changed');
// Native axes mirror GTA heading. Assert the actual current parser boundary,
// then evaluate authored angles; this is source conformance, not Swift runtime.
const nativeTP=native.slice(native.indexOf('        case "tp":'),native.indexOf('        default: break',native.indexOf('        case "tp":')));
check(/-\$0\.floatValue\s*\*\s*\.pi\s*\/\s*180/.test(nativeTP),'Native TP consumer no longer converts degrees; re-audit contract');
equal((source.match(/\bt:\s*['"]tp['"]/g)||[]).length,6,'TP producer inventory changed: add actual-path coverage');
const helper=source.match(/function tpHeadingFromRadians\(value\)\s*\{[^}]+\}/)?.[0]||'';

function fixture(degrees){
  const home={id:'authored-home',name:'Authored home',kind:'authored-room',out:[100,200,20,degrees]};
  const entry=[110,210,900,degrees],radians=degrees*Math.PI/180;
  const airports=[{id:'a',name:'Authored airport A',stand:[100,200,20],runway:[120,220,25,radians]},
    {id:'b',name:'Authored airport B',stand:[500,500,20],runway:[500,500,25,0]}];
  const context={finite:(v,f=0)=>Number.isFinite(v)?v:f,
    rounded:(v,f=0)=>Math.round((Number.isFinite(v)?v:f)*1000)/1000,
    HOME_CATALOG:[home],homeAt:id=>id===home.id?home:null,
    clientCatalog:{interior_spawns:{'authored-room':entry}},
    JOBS:[{id:'pilot'}],AIRPORTS:airports,CAR_CATALOG:[{model:593}],
    pilotAircraft:()=>({model:593,name:'Authored aircraft',level:1}),pilotLevel:()=>1,
    missionId:()=> 'synthetic-mission'};
  const Type=vm.runInNewContext(helper+'\n'+source.slice(begin,end)+'\nLocalGame;',context);
  const game=Object.create(Type.prototype),packets=[];
  const player={number:1,health:73,armour:11,homes:[home.id],insideHome:null,job:null,
    inventory:{selected:22,revision:3,weapons:{22:{clip:5,rest:10}}}};
  const peer={player,ready:true,closed:false,lastSeen:Date.now(),
    state:{walking:true,skin:7,x:100,y:200,z:20,heading:radians,pitch:0,roll:0},
    send:m=>packets.push(structuredClone(m))};
  Object.assign(game,{peers:new Set([peer]),passengerClaims:new Map(),vehicles:new Map(),race:null});
  game.expireRace=()=>{};game.note=()=>{};game.gameplayState=()=>({});game.save=()=>{};
  let created=0;game.addMissionVehicle=()=>created++;
  return{game,player,peer,packets,home,entry,airports,created:()=>created};
}
const angles=[-720,-180,-90,-40,-.001,0,.001,39.5340878640268,45,90,90.25,180,270,720];
const paths=['home.enter','home.exit','home.visit','pilot.start','passenger.release','passenger.reject'];
for(const degrees of angles)for(const producer of paths){
  const f=fixture(degrees),inventory=structuredClone(f.player.inventory);
  let expectedPoint;
  if(producer==='home.enter'){
    f.game.action(f.player,'home.enter',{home:f.home.id});expectedPoint=f.entry.slice(0,3);
    equal(f.player.insideHome,f.home.id,'Home enter state lost');
  }else if(producer==='home.exit'){
    f.player.insideHome=f.home.id;[f.peer.state.x,f.peer.state.y,f.peer.state.z]=f.entry;
    f.game.action(f.player,'home.exit',{});expectedPoint=f.home.out.slice(0,3);
    equal(f.player.insideHome,null,'Home exit state lost');
  }else if(producer==='home.visit'){
    f.game.action(f.player,'home.visit',{home:f.home.id});expectedPoint=f.home.out.slice(0,3);
  }else if(producer==='pilot.start'){
    f.game.action(f.player,'job.start',{job:'pilot',model:593});
    const runway=f.airports[0].runway;
    expectedPoint=[Math.round((runway[0]-Math.sin(runway[3])*7)*1000)/1000,
      Math.round((runway[1]-Math.cos(runway[3])*7)*1000)/1000,runway[2]+1];
    equal(f.created(),1,'Pilot mission creation changed');equal(f.player.job.stage,'takeoff','Pilot start state changed');
  }else if(producer==='passenger.release'){
    const vehicle={id:'synthetic-taxi',row:['synthetic-taxi','Authored','420.6.1.0.',100,200,20,degrees*Math.PI/180,0,0,800]};
    const claim={peer:f.peer,vehicle,seat:1,active:true};
    f.game.vehicles.set(vehicle.id,vehicle);f.game.passengerClaims.set(f.peer,claim);
    f.game.releasePassengerClaim(claim,{correct:true});expectedPoint=[100,200,20];
    equal(f.game.passengerClaims.size,0,'Passenger release authority changed');
    equal(vehicle.row[9],800,'Passenger correction repaired hull');
  }else{
    const result=f.game.preparePassengerReport(f.peer,{walking:false,driving:true,skin:7,riding:'unknown',seat:1});
    equal(result,null,'Invalid passenger report no longer rejected');expectedPoint=[100,200,20];
  }
  const teleports=f.packets.filter(m=>m.t==='tp');equal(teleports.length,1,producer+' TP count');
  const tp=teleports[0];equal([tp.x,tp.y,tp.z],expectedPoint,producer+' coordinates changed');
  equal(tp.g,1,producer+' ground policy changed');
  equal([f.player.health,f.player.armour],[73,11],producer+' changed vitals');
  equal(f.player.inventory,inventory,producer+' changed ammunition');
  if(!near(tp.h,degrees))mismatches.push({producer,inputDegrees:degrees,wireHeading:tp.h,expected:degrees});
  if(!historical){check(near(tp.h,degrees),producer+' TP.h must be degrees');
    check(near(-tp.h*Math.PI/180,-degrees*Math.PI/180),producer+' native-heading contract');}
  outcomes.push({producer,inputDegrees:degrees,wireHeading:tp.h,passed:near(tp.h,degrees)});
}
if(historical){
  equal([...new Set(mismatches.map(m=>m.producer))].sort(),['home.enter','home.exit','home.visit','pilot.start'],
    'Historical negative must isolate four broken producers, retaining correct passenger cases');
  equal(mismatches.length,(angles.length-1)*4,'Historical mismatch count changed');
}else equal(mismatches,[],'Heading mismatch');
const report={status:historical?'HISTORICAL_FOUR_PRODUCER_MISMATCH_REPRODUCED':'PASS',checks,
  actualPathCases:outcomes.length,producerCount:paths.length,backendSHA256:sha(source),
  nativeParserSHA256:sha(native),mismatches,outcomes,
  limits:['Actual LocalGame methods, authored catalogues/transports, no constructor/listener/timers/save.',
    'Native parser check is actual-source conformance plus authored arithmetic; no Swift or device execution.',
    'Archived browser consumer execution is a separate private evidence carrier; no original bytes embedded here.',
    'No UI/server runtime acceptance, retail orientation claim, geometry or authority policy change.']};
const out=path.join(__dirname,'local-only/research/server-tp-units-113');fs.mkdirSync(out,{recursive:true});
const name=historical?'historical-report.json':'report.json';
fs.writeFileSync(path.join(out,name),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({status:report.status,checks,cases:outcomes.length,producers:paths.length,mismatches:mismatches.length,backendSHA256:report.backendSHA256}));
