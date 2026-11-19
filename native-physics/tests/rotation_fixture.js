#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('../../tests/vehicles/smoke_vehicle_dynamics');
(async()=>{const R=archivedModules()(55077);await R.init();const world=new R.World({x:0,y:0,z:0});
const cases=[];for(const kind of ['velocity','position']){
 const body=world.createRigidBody(kind==='velocity'?R.RigidBodyDesc.kinematicVelocityBased():R.RigidBodyDesc.kinematicPositionBased());
 const samples=[[.1,.2,.3,.9273618],[.5,-.3,.1,.7],[0,0,0,0],[-.001,.0002,.0003,.999998]];
 for(const q of samples){const value={x:q[0],y:q[1],z:q[2],w:q[3]};
  if(kind==='velocity')body.setRotation(value,true);else body.setNextKinematicRotation(value);
  const before=body.rotation();world.step();const after=body.rotation();
  cases.push({kind,input:q,before:[before.x,before.y,before.z,before.w],after:[after.x,after.y,after.z,after.w]});
 }world.removeRigidBody(body);
}
const out=path.resolve(__dirname,'../../local-only/physics-fixtures/browser-rotation.json');
fs.writeFileSync(out,JSON.stringify({version:1,cases}),{mode:0o600});world.free();console.log('PASS: recorded actual JS rotation setter boundary');
})().catch(error=>{console.error(error.message);process.exitCode=1});
