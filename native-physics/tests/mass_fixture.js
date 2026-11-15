#!/usr/bin/env node
// Actual JS binding timing for creation, pending additional mass and explicit
// recomputation. Generated state stays in ignored local-only/.
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('../../smoke_vehicle_dynamics');
async function main(){
  const R=archivedModules()(55077);await R.init();
  const world=new R.World({x:0,y:0,z:0}),com={x:.2,y:0,z:0},frame={x:0,y:0,z:0,w:1};
  const inertia=mass=>({x:mass,y:mass,z:mass});
  const body=world.createRigidBody(R.RigidBodyDesc.dynamic().setCanSleep(false).setCcdEnabled(true)
    .setAdditionalMassProperties(100,com,inertia(100),frame));
  world.createCollider(R.ColliderDesc.ball(.3).setDensity(0),body);
  const output=[];
  const snapshot=label=>{const v=body.linvel(),w=body.angvel();output.push({label,mass:body.mass(),velocity:[v.x,v.y,v.z],angular:[w.x,w.y,w.z]});};
  const push=()=>body.applyImpulse({x:100,y:0,z:0},true);
  snapshot('created');push();snapshot('impulse-before-step');world.step();snapshot('first-step');push();snapshot('impulse-after-step');
  body.setAdditionalMassProperties(200,com,inertia(200),frame,true);snapshot('mass-set-pending');push();snapshot('impulse-pending-mass');
  world.step();snapshot('mass-set-step');push();snapshot('impulse-new-mass');
  body.setAdditionalMassProperties(400,com,inertia(400),frame,true);snapshot('second-mass-pending');
  body.recomputeMassPropertiesFromColliders();snapshot('explicit-recompute');push();snapshot('explicit-mass-impulse');
  const file=path.join(__dirname,'../../local-only/native-physics/tests/mass-reference.json');fs.mkdirSync(path.dirname(file),{recursive:true});
  fs.writeFileSync(file,JSON.stringify(output),{mode:0o600});console.log(JSON.stringify(output));world.free();
}
if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1;});
