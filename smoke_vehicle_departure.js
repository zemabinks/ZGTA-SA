#!/usr/bin/env node
// Actual public manager clauses distinguish streamed omission, explicit gone,
// and a currently held vehicle. Original models remain ignored local data.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {createLibrary}=require('./prepare_native_vehicle_rigs');
const {managerFactory}=require('./smoke_unattended_vehicles');
async function main(){
 const lib=createLibrary(),R=lib.load(55077);await R.init();const T=lib.T,{make,clock}=managerFactory(lib);
 const rows=JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/site/game/native/vehicles.physics.json'))).models;
 let checks=0;
 for(const model of [420,522,481,430,519,487,435])for(const held of [false,true]){
  const world=new R.World({x:0,y:-18,z:0}),environment={RAPIER:R,world,others:new Set,waterLevel:()=>null,below:()=>null};
  const packets=[],manager=make({scene:new T.YJl(),onMove:(id,state)=>packets.push({id,state}),held:()=>held?'test':null});manager.setPhysics(environment);
  const raw=rows[model],scene=lib.build(model),built={...raw,...scene,id:String(model),bounds:raw.bounds,origin:raw.origin,kind:raw.kind,body:scene.body,root:scene.root,wheels:scene.wheels,dispose(){},setLights(){}};
  const group=new T.YJl();group.position.set(3,2,0);group.add(built.body);
  const entry={id:'test',group,built,driver:null,health:1000,damage:'',work:0,solids:[],rig:null,body:null,alive:true,target:{position:group.position.clone(),quaternion:group.quaternion.clone()},eased:true,wreck:lib.load(39851).k(built),doors:lib.load(66242)._E(built.table,built.bounds,built.table.modelFlags,model),held:new Map,asked:1};
  const native=manager.native();native.N.set(entry.id,entry);native.G(entry,new T.Pq0(3,0,0));
  assert(entry.rig);const rigid=entry.rig.rigid,handles=[...environment.others];assert(handles.length>0);checks+=2;
  manager.hear([],true);assert.equal(manager.get(entry.id),entry,'Full-list omission must preserve promoted prediction');assert(rigid.isValid());checks+=2;
  manager.gone(entry.id);
  if(held){assert.equal(manager.get(entry.id),entry);assert(rigid.isValid());assert.equal(entry.local,true);checks+=3;}
  else{
   assert.equal(manager.get(entry.id),null);assert.equal(rigid.isValid(),false);assert.equal(environment.others.size,0);checks+=3;
   manager.gone(entry.id);clock.value+=1000;const previous=packets.length;manager.update(clock.value,1/60,null);manager.beforeStep(1/60);world.step();manager.afterStep(1/60);assert.equal(packets.length,previous,'Gone manager emitted old motion');checks++;
  }
  manager.dispose();assert.equal(environment.others.size,0);checks++;world.free();
 }
 console.log('PASS actual browser vehicle departure:',checks,'checks across seven model classes; omission retains, gone disposes, held ownership survives');
}
if(require.main===module)main().catch(error=>{console.error(error.stack);process.exitCode=1});
