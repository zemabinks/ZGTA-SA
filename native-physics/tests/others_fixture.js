#!/usr/bin/env node
// Actual original23895.vX parked chassis and Rapier shape ray references.
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require('../../smoke_vehicle_dynamics');
async function main(){
 const load=archivedModules(),R=load(55077);await R.init();const T=load(85339),original=load(23895),groups=load(39943),root=path.resolve(__dirname,'../..'),models=JSON.parse(fs.readFileSync(path.join(root,'local-only/site/game/native/vehicles.physics.json'))).models,cases=[];
 for(const model of [420,432,449,481,520,539])for(const tilted of [false,true]){
  const raw=models[model],heading=tilted?Math.fround(.7):0,pitch=tilted?Math.fround(.1):0,roll=tilted?Math.fround(-.15):0,world=new R.World({x:0,y:0,z:0});
  const q=new T.PTz().setFromAxisAngle(new T.Pq0(0,1,0),-heading).multiply(new T.PTz().setFromAxisAngle(new T.Pq0(1,0,0),pitch)).multiply(new T.PTz().setFromAxisAngle(new T.Pq0(0,0,1),-roll));
  const body=world.createRigidBody(R.RigidBodyDesc.kinematicPositionBased().setRotation(q));
  const built={...raw,id:String(model),wheels:raw.wheels.map(w=>({...w,centre:new T.Pq0(...w.centre)}))};
  const colliders=original.vX({RAPIER:R,world},built,body,groups.fd.PARKED);if(raw.kind!=='train')for(const c of colliders)c.setSolverGroups(groups.vu.OTHERS);
  world.step();const rays=[];
  for(const x of [-3,-1.5,0,1.5,3])for(const z of [-5,-2,0,2,5])rays.push({origin:[x,15,z],direction:[0,-1,0],distance:30});
  for(const x of [-2,0,2])for(const y of [.3,1.2,2.5])rays.push({origin:[x,y,-15],direction:[0,0,1],distance:30});
  for(const z of [-3,0,3])for(const y of [.3,1.2,2.5])rays.push({origin:[-15,y,z],direction:[1,0,0],distance:30});
  for(const ray of rays){const o=new T.Pq0(...ray.origin),d=new T.Pq0(...ray.direction),hit=world.castRayAndGetNormal(new R.Ray(o,d),ray.distance,true);ray.expected=hit?{distance:hit.timeOfImpact,normal:[hit.normal.x,hit.normal.y,hit.normal.z],piece:colliders.pieces.get(hit.collider.handle)}:null}
  cases.push({model,heading,pitch,roll,count:colliders.length,rays});world.free();
 }
 fs.writeFileSync(path.join(root,'local-only/physics-fixtures/other-vehicles.json'),JSON.stringify({version:1,cases}),{mode:0o600});console.log('PASS original parked chassis references:',cases.length,'models/poses,',cases.reduce((n,c)=>n+c.rays.length,0),'rays');
}
main().catch(e=>{console.error(e);process.exitCode=1});
