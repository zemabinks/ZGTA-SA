#!/usr/bin/env node
// Executes the archived engine offline; the source and generated measurements
// stay local. This records engine contact events, not publisher damage rules.
const fs = require('node:fs');
const path = require('node:path');
const {archivedModules} = require('../../smoke_vehicle_dynamics');
async function main() {
  const R = archivedModules()(55077); await R.init();
  const world = new R.World({x:0,y:-9.81,z:0});
  const floor = world.createCollider(R.ColliderDesc.cuboid(20,0.1,20));
  const body = world.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(0,3,0)
    .setCcdEnabled(true).setCanSleep(false).setAdditionalMassProperties(10,{x:0,y:0,z:0},
      {x:2,y:2,z:2},{x:0,y:0,z:0,w:1}));
  const shape = world.createCollider(R.ColliderDesc.ball(0.5).setDensity(0)
    .setFriction(0.5).setFrictionCombineRule(R.CoefficientCombineRule.Min)
    .setActiveEvents(R.ActiveEvents.CONTACT_FORCE_EVENTS),body);
  const queue = new R.EventQueue(true), frames = [];
  const vector = v => [v.x,v.y,v.z];
  for(let index=0;index<120;index++) {
    world.step(queue); const events=[];
    queue.drainContactForceEvents(event => events.push({
      first: event.collider1()===shape.handle?'body':'floor',
      second: event.collider2()===shape.handle?'body':'floor',
      force: vector(event.totalForce()),magnitude:event.totalForceMagnitude(),
      maxDirection:vector(event.maxForceDirection()),maxMagnitude:event.maxForceMagnitude(),
    }));
    frames.push({position:vector(body.translation()),velocity:vector(body.linvel()),events});
  }
  if(!frames.some(frame=>frame.events.length))throw new Error('Original engine emitted no contact events');
  const destination=path.resolve(__dirname,'../../local-only/physics-fixtures/contact-events.json');
  fs.mkdirSync(path.dirname(destination),{recursive:true});
  fs.writeFileSync(destination,JSON.stringify({version:1,engine:R.version(),frames}),{mode:0o600});
  queue.free();world.free();console.log('PASS: recorded actual archived Rapier contact-force events offline');
}
main().catch(error=>{console.error(error);process.exitCode=1});
