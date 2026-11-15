#!/usr/bin/env node
// Observe original body/collider/query synchronization, without inventing a
// replacement broadphase or changing current native immediate-query callers.
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('../../smoke_vehicle_dynamics');
async function main(){
  const R=archivedModules()(55077);await R.init();const world=new R.World({x:0,y:0,z:0});
  const body=world.createRigidBody(R.RigidBodyDesc.kinematicPositionBased().setTranslation(0,1,0));
  const collider=world.createCollider(R.ColliderDesc.ball(.5),body),rows=[];
  const xyz=v=>[v.x,v.y,v.z];
  function ray(x){const hit=world.castRay(new R.Ray({x:x-3,y:1,z:0},{x:1,y:0,z:0}),5,true);return hit?{distance:hit.timeOfImpact,own:hit.collider.handle===collider.handle}:null;}
  function snapshot(label){rows.push({label,body:xyz(body.translation()),collider:xyz(collider.translation()),old:ray(0),at10:ray(10),at20:ray(20),at30:ray(30),afterQueryCollider:xyz(collider.translation())});}
  snapshot('created-before-step');world.step();snapshot('first-step');body.setTranslation({x:10,y:1,z:0},true);snapshot('body-set-before-step');
  if(typeof world.propagateModifiedBodyPositionsToColliders==='function'){world.propagateModifiedBodyPositionsToColliders();snapshot('explicit-body-propagation');}
  world.step();snapshot('body-set-after-step');collider.setTranslation({x:20,y:1,z:0});snapshot('collider-set-before-step');
  const added=world.createCollider(R.ColliderDesc.ball(.5).setTranslation(30,1,0));snapshot('new-collider-before-step');world.step();snapshot('collider-set-after-step');
  added.setEnabled(false);snapshot('disabled-before-step');world.free();
  const file=path.join(__dirname,'../../local-only/native-physics/tests/query-timing-reference.json');fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify(rows),{mode:0o600});
  console.log(JSON.stringify(rows));
}
if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1;});
