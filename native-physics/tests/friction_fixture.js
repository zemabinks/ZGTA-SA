#!/usr/bin/env node
// Synthetic original-engine fixture for the source trailer-leg Average rule.
// Calibration shapes are explicit; no publisher vehicle geometry is invented.
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('../../smoke_vehicle_dynamics');
async function main(){
  const R=archivedModules()(55077);await R.init();
  const cases=[];
  for(const floorRule of ['Average','Min'])for(const bodyRule of ['Average','Min']){
    const world=new R.World({x:0,y:-18,z:0});
    const vertices=new Float32Array([-100,0,-100,100,0,-100,100,0,100,-100,0,100]);
    const indices=new Uint32Array([0,2,1,0,3,2]);
    world.createCollider(R.ColliderDesc.trimesh(vertices,indices).setFriction(.8).setFrictionCombineRule(R.CoefficientCombineRule[floorRule]));
    const body=world.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(0,.3,0).setLinvel(6,0,0).setCanSleep(false).setCcdEnabled(true)
      .setAdditionalMassProperties(100,{x:0,y:0,z:0},{x:10000,y:10000,z:10000},{x:0,y:0,z:0,w:1}));
    world.createCollider(R.ColliderDesc.ball(.3).setDensity(0).setFriction(1).setFrictionCombineRule(R.CoefficientCombineRule[bodyRule]),body);
    const frames=[];
    for(let i=0;i<120;i++){
      world.step();const p=body.translation(),q=body.rotation(),v=body.linvel(),w=body.angvel();
      frames.push({position:[p.x,p.y,p.z],rotation:[q.x,q.y,q.z,q.w],velocity:[v.x,v.y,v.z],angular:[w.x,w.y,w.z]});
    }
    cases.push({floorRule,bodyRule,frames});world.free();
  }
  const output=path.join(__dirname,'../../local-only/native-physics/tests/friction-reference.json');
  fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,JSON.stringify(cases),{mode:0o600});
  console.log(JSON.stringify(cases.map(c=>({floor:c.floorRule,body:c.bodyRule,at30:c.frames[29].position[0],at120:c.frames[119].position[0]}))));
}
if(require.main===module)main().catch(e=>{console.error(e);process.exitCode=1;});
