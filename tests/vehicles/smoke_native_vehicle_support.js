#!/usr/bin/env node
'use strict';
// Execute the owner-local archived parked manager. No original model data or
// recorded frames are embedded in this independent reference runner.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {createLibrary}=require('../../tools/assets/prepare_native_vehicle_rigs');
const {managerFactory}=require('./smoke_unattended_vehicles');
const vector=v=>[v.x,v.y,v.z],quaternion=q=>[q.x,q.y,q.z,q.w];
async function main(){
 const library=createLibrary(),load=library.load,R=load(55077),T=library.T;await R.init();
 const models=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/vehicles.physics.json'))).models;
 function fresh(id,floor=false){
  const world=new R.World({x:0,y:-18,z:0});
  if(floor){world.createCollider(R.ColliderDesc.cuboid(1000,.1,1000).setTranslation(0,-.1,0).setFriction(.8).setCollisionGroups(131071));world.step()}
  const {make}=managerFactory(library),environment={RAPIER:R,world,others:new Set,waterLevel:()=>null,below:()=>null};
  const manager=make({scene:new T.YJl(),onMove:()=>{}});manager.setPhysics(environment);
  const scene=library.build(id),built={...models[id],...scene,id:String(id),bounds:models[id].bounds,origin:models[id].origin,kind:models[id].kind,
    collision:scene.parsed.collision,dispose(){},setLights(){}};
  const group=new T.YJl();group.position.y=1.1;group.add(built.body);
  const entry={id:'fixture',group,built,driver:null,health:1000,damage:'',work:0,solids:[],rig:null,body:null,alive:true,
    target:{position:group.position.clone(),quaternion:group.quaternion.clone()},eased:true,wreck:load(39851).k(built),
    doors:load(66242)._E(built.table,built.bounds,built.table.modelFlags,id),held:new Map,asked:1};
  manager.native().N.set(entry.id,entry);manager.native().G(entry);
  return{world,manager,environment,entry,close(){manager.dispose();world.free();library.geometry.xd(scene.root,null)}};
 }
 const profiles=[];
 for(const model of Object.values(models).filter(row=>row.kind==='trailer')){
  const s=fresh(model.id),leg=s.entry.leg,original=s.entry.rig.rigid;
  const descriptor=leg?{radius:leg.radius(),local:[0,.3,.55*s.entry.built.coupling.configuration(s.entry.built).trailerAnchor[2]],
    world:vector(leg.translation()),density:leg.density(),friction:leg.friction(),restitution:leg.restitution(),
    collision:leg.collisionGroups(),solver:leg.solverGroups(),combine:leg.frictionCombineRule()}:null;
  original.setLinvel({x:3,y:1,z:-2},true);original.setAngvel({x:.1,y:.2,z:.3},true);
  s.manager.haul(s.entry.id);const held=s.entry.rig.rigid;
  const haul={support:!!s.entry.leg,originalBodyValid:original.isValid(),linear:vector(held.linvel()),angular:vector(held.angvel())};
  s.manager.unhaul(s.entry.id);
  profiles.push({id:model.id,descriptor,haul,release:{support:!!s.entry.leg,sameBody:s.entry.rig.rigid===held,registered:!!s.entry.leg&&s.environment.others.has(s.entry.leg.handle)}});s.close();
 }
 const trajectories=[];
 for(const id of [435,610,606])for(const removeSupport of [false,true]){
  const s=fresh(id,true),hadSupport=!!s.entry.leg;
  if(removeSupport&&s.entry.leg){s.environment.others.delete(s.entry.leg.handle);s.world.removeCollider(s.entry.leg,true);s.entry.leg=null}
  const frames=[];
  for(let i=0;i<180;i++){
   s.manager.beforeStep(1/60);s.world.step();s.manager.afterStep(1/60);const body=s.entry.rig.rigid;
   frames.push({position:vector(body.translation()),rotation:quaternion(body.rotation()),linear:vector(body.linvel()),angular:vector(body.angvel())});
  }
  trajectories.push({id,removeSupport,hadSupport,frames});s.close();
 }
 // The archived world loader creates a .8-friction trimesh without a combine
 // override. Its default-average contact with a default-average support ball
 // must remain different from the chassis' explicit minimum rule.
 const world=new R.World({x:0,y:-18,z:0});
 const points=new Float32Array([-100,0,-100,100,0,-100,100,0,100,-100,0,100]),indices=new Uint32Array([0,2,1,0,3,2]);
 world.createCollider(R.ColliderDesc.trimesh(points,indices).setFriction(.8));
 const body=world.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(0,.31,0).setGravityScale(1)
  .setAdditionalMassProperties(25,{x:0,y:0,z:0},{x:25,y:25,z:25},{x:0,y:0,z:0,w:1}));
 world.createCollider(R.ColliderDesc.ball(.3).setDensity(0).setFriction(1),body);body.setLinvel({x:2,y:0,z:0},true);
 const friction=[];for(let i=0;i<120;i++){world.step();friction.push({position:vector(body.translation()),rotation:quaternion(body.rotation()),linear:vector(body.linvel()),angular:vector(body.angvel())})}world.free();
 const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
 const report={sourceSHA256:hash(load.factories[19737].toString()),profiles,trajectories,friction,
  limits:['Actual archived manager with owner-local data; source default-average test floor','Support-removal trajectories are explicitly controlled ablations; no original retail or physical device execution']};
 fs.writeFileSync(process.argv[2],JSON.stringify(report),{mode:0o600});
 console.log(`Recorded ${profiles.length} trailer profiles and ${trajectories.length*180} physical support frames`);
}
main().catch(error=>{console.error(error.stack);process.exitCode=1});
