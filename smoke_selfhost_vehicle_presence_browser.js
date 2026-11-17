#!/usr/bin/env node
'use strict';
// Offline execution of the owner's archived browser manager and its actual
// veh/spawned/vgone dispatch. Original source, models and reports stay local-only.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {createLibrary}=require('./prepare_native_vehicle_rigs');
const {managerFactory}=require('./smoke_unattended_vehicles');
const OUT=path.join(__dirname,'local-only/research/vehicle-presence');
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
async function main(){
 const lib=createLibrary(),T=lib.T,R=lib.load(55077);await R.init();
 const factory=lib.load.factories[19737].toString(),{make,clock}=managerFactory(lib);
 const start=factory.indexOf('else if("veh"===l.t||"spawned"===l.t)'),end=factory.indexOf('else if("obj"===l.t)',start);
 assert(start>=0&&end>start,'Archived network vehicle dispatch signature changed');
 const dispatch=Function('E','l','A','let c;'+factory.slice(start+5,end));
 const ownStart=factory.indexOf('own:()=>{var e,t,l;if(!er.dataset.ready)'),ownEnd=factory.indexOf(',onNews:',ownStart);
 assert(ownStart>=0&&ownEnd>ownStart,'Archived own-report serializer signature changed');
 // These are synthetic engine inputs, not a replacement serializer. Execute
 // the unchanged original own() body to distinguish local from registry cars.
 const ownScope={er:{dataset:{ready:true}},lT:true,l_:false,lA:false,
  cj:{ready:true,parked:false,car:{position:{x:100,y:100,z:20}},stance:()=>({heading:0,pitch:0,roll:0,health:1000})},
  tC:point=>({...point}),cG:{id:'serializer-logical',carText:'420.6.1.0.',local:true},oF:{current:''},
  c6:{skin:7,health:100,armour:0,dead:false},uy:{act:0},dF:false,c7:{aiming:false},iE:{horn:false,siren:false},uw:()=>null,
  performance:clock,Math};
 const ownProxy=new Proxy(ownScope,{has:()=>true,get(target,key){if(key===Symbol.unscopables)return undefined;if(key in target)return target[key];throw Error('Unprovided own serializer dependency '+String(key));}});
 const own=Function('scope','with(scope){return ('+factory.slice(ownStart+4,ownEnd)+')}')(ownProxy);
 const localReport=own();assert(localReport.driving===true&&!Object.hasOwn(localReport,'vehicle'),'Original local car unexpectedly claims registry identity');
 ownScope.cG.local=false;const registryReport=own();assert.equal(registryReport.vehicle,'serializer-logical');
 const models=JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/site/game/native/vehicles.physics.json'))).models;
 let checks=2;const cases=[];
 const check=(value,label)=>{checks++;assert(value,label);};
 const equal=(value,wanted,label)=>{checks++;assert.deepEqual(value,wanted,label);};
 function fixture(model,id='presence',carText=String(model)){
  clock.value=1000;let handed=false,held=false;
  const world=new R.World({x:0,y:-18,z:0}),environment={RAPIER:R,world,others:new Set,waterLevel:()=>null,below:()=>null};
  const manager=make({scene:new T.YJl(),handed:key=>handed&&key===id,held:()=>held?id:null});manager.setPhysics(environment);
  const raw=models[model],scene=lib.build(model),built={...raw,...scene,id:String(model),bounds:raw.bounds,origin:raw.origin,kind:raw.kind,body:scene.body,root:scene.root,wheels:scene.wheels,dispose(){},setLights(){}};
  const group=new T.YJl();group.position.set(100,20,-100);group.add(built.body);
  const entry={id,carText,group,built,driver:null,health:1000,damage:'',work:0,solids:[],rig:null,body:null,alive:true,target:{position:group.position.clone(),quaternion:group.quaternion.clone()},eased:true,wreck:lib.load(39851).k(built),doors:lib.load(66242)._E(built.table,built.bounds,built.table.modelFlags,model),held:new Map,asked:1};
  manager.native().N.set(id,entry);manager.native().G(entry,new T.Pq0(3,0,0));
  const row=(driver=null,extra={})=>Object.assign([id,'SyntheticOwner',carText,100,100,20,0,0,0,1000,'',driver,null,null,null,0,0],extra);
  const tick=()=>{clock.value+=16;manager.update(clock.value,1/60,null);};
  return{manager,entry,world,row,tick,setHanded:v=>{handed=v},setHeld:v=>{held=v},close(){manager.dispose();world.free();}};
 }
 // Sensitivity check: the104-style missing occupancy marker really does leave
 // a second parked body alive when the matching driven representation exists.
 const missing=fixture(420);try{missing.setHanded(true);dispatch(missing.manager,{t:'veh',v:missing.row()},null);missing.tick();check(missing.entry.group.visible,'Negative contract no longer reproduces the unmarked parked duplicate');}finally{missing.close();}
 for(const model of [420,522,481,430,519,487,435]){
  const f=fixture(model),{manager,entry,row,tick}=f;const first=checks;
  try{
   dispatch(manager,{t:'veh',v:row()},null);tick();check(entry.group.visible,`${model}: parked/pending entry is invisible`);
   equal(manager.get(entry.id),entry,`${model}: parked logical entry replaced`);
   const rigid=entry.rig?.rigid || entry.body;check(rigid?.isValid(),`${model}: parked physical body absent`);
   dispatch(manager,{t:'veh',v:row('2')},null);tick();check(entry.group.visible,`${model}: occupied row hid before actual driven representation existed`);
   f.setHanded(true);tick();check(!entry.group.visible,`${model}: occupied parked body duplicated driven representation`);
   check(!rigid.isValid(),`${model}: hidden parked physics remained active`);equal(manager.get(entry.id),entry,`${model}: occupancy deleted logical metadata`);
   f.setHanded(false);const final=row(null,{3:104,4:102,5:21,6:.7,7:.1,8:-.2,9:650,10:'',16:777});
   dispatch(manager,{t:'veh',v:final},null);tick();check(entry.group.visible,`${model}: same-ID final park failed immediate restore`);
   equal(manager.get(entry.id),entry,`${model}: final park replaced identity`);equal(entry.driver,null,`${model}: final park retained driver marker`);
   equal([entry.target.position.x,entry.target.position.y,entry.target.position.z],[104,21,-102],`${model}: final world/basis pose lost`);
   equal([entry.health,entry.damage,entry.work],[650,'',777],`${model}: final condition/work lost`);
   check(entry.rig?.rigid.isValid()||entry.body?.isValid(),`${model}: parked physical collision not restored`);
   // Local get-in/get-out uses the same logical record, not network vgone.
   f.setHeld(true);const take=manager.take(entry.id,'me');check(take&&entry.driver==='me'&&!entry.group.visible,`${model}: local take failed`);
   dispatch(manager,{t:'veh',v:row('2')},null);check(manager.get(entry.id)===entry,`${model}: driver echo destroyed local held identity`);
   manager.park(entry.id,{...take,position:new T.Pq0(106,21,-103),quaternion:new T.PTz(),health:640,damage:'',work:333});f.setHeld(false);
   dispatch(manager,{t:'veh',v:row(null,{3:106,4:103,5:21,9:640,16:333})},null);tick();
   check(entry.group.visible&&entry.driver===null,`${model}: local release left occupied or invisible`);
   cases.push({model,checks:checks-first,passed:true});
  }finally{f.close();}
 }
 // Replay actual observed HTTP/WebSocket packets from the independent fixture
 // through the archived dispatch. Synthetic model8001 uses owner-local420
 // geometry solely to exercise this manager; no geometry result is claimed.
 const server=JSON.parse(fs.readFileSync(path.join(OUT,'server-report.json')));
 const backendHash=hash(fs.readFileSync(path.join(__dirname,'selfhost_backend.js')));
 equal(server.sourceSHA256['selfhost_backend.js'],backendHash,'Server wire capture is stale');
 const f=fixture(420,'publication','8001.4.5.0.');let sawOccupied=false,sawDrive=false,sawRestore=false,packets=0;
 try{
  for(const message of server.observedWire){
   if(['veh','spawned'].includes(message.t)&&message.v[0]==='publication'){
    dispatch(f.manager,message,null);packets++;
    if(message.v[11])sawOccupied=true;
    else if(sawDrive)sawRestore=true;
   }else if(message.t==='cars'){
    const driving=message.c.some(row=>row[35]==='publication'&&row[2]==='8001.4.5.0.');
    f.setHanded(driving);if(driving){check(sawOccupied,'Real first driving row preceded occupied metadata');sawDrive=true;}
   }else if(message.t==='vgone'&&message.id==='publication')throw Error('Real occupancy used a destructive browser tombstone');
   f.tick();
   if(sawDrive&&!sawRestore&&f.entry.driver)check(!f.entry.group.visible,'Real wire produces simultaneous parked and driven bodies');
  }
  check(sawOccupied&&sawDrive&&sawRestore,'Actual wire replay missed a full occupied/release cycle');
  equal(f.manager.get('publication'),f.entry,'Actual wire lost logical vehicle identity');
  check(f.entry.group.visible&&f.entry.driver===null,'Actual wire did not restore parked visibility');
  equal([f.entry.target.position.x,f.entry.target.position.y,f.entry.target.position.z],[104,20,-102],'Actual wire final pose changed');
  equal([f.entry.health,f.entry.damage,f.entry.work],[800,'fixture-damage',2300],'Actual wire final condition/work changed');
 }finally{f.close();}
 // New occupied snapshot parsing is checked without pretending an asset loader
 // finished: the actual archive owns that asynchronous load; fetch is disabled.
 clock.value=10000;const late=make({scene:new T.YJl(),handed:()=>true});
 dispatch(late,{t:'veh',v:['late','Synthetic','420',100,100,20,0,0,0,900,'','2']},null);late.update(clock.value,1/60,null);
 const lateEntry=late.get('late');check(lateEntry?.driver==='2'&&!lateEntry.group.visible,'New occupied snapshot appeared parked');late.dispose();
 fs.mkdirSync(OUT,{recursive:true});
 fs.writeFileSync(path.join(OUT,'browser-serializer-report.json'),JSON.stringify({schema:1,archivedFactory19737SHA256:hash(factory),serializerSHA256:hash(factory.slice(ownStart+4,ownEnd)),inputs:'Synthetic finite engine values; actual unchanged archived own() serializer.',localReport,registryReport},null,2)+'\n');
 fs.writeFileSync(path.join(OUT,'browser-manager-report.json'),JSON.stringify({passed:true,checks,cases,observedPacketsReplayed:packets,backendSHA256:backendHash,archivedFactory19737SHA256:hash(factory),dispatchSHA256:hash(factory.slice(start,end)),testSHA256:hash(fs.readFileSync(__filename)),evidence:'Actual archived manager/dispatch/own serializer offline VM, owner-local original geometry and Rapier, real synthetic server wire replay; fetch disabled.',limits:'No GPU, retail physics, human input, live browser or device acceptance. Late-entry asset load completion is not claimed.'},null,2)+'\n');
 console.log(`PASS actual archived vehicle presence: ${checks} checks across ${cases.length} model classes and real server wire replay`);
}
if(require.main===module)main().catch(error=>{console.error(error.stack);process.exitCode=1});
