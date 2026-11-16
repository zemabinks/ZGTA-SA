#!/usr/bin/env node
// Public Rapier API exercised through the owner's actual archived WASM.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{archivedModules}=require('../../smoke_vehicle_dynamics');
async function main(){
 const load=archivedModules(),R=load(55077);await R.init();const cases=[];
 const v=a=>({x:a[0],y:a[1],z:a[2]}),state=b=>{
  const p=b.translation(),q=b.rotation(),l=b.linvel(),a=b.angvel();
  return [p.x,p.y,p.z,q.x,q.y,q.z,q.w,l.x,l.y,l.z,a.x,a.y,a.z];
 };
 for(const masses of [[10,10],[1000,1800],[1400,5000]])for(const contacts of [false,true]){
  const world=new R.World(v([0,0,0]));
  function body(z,mass){return world.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(0,0,z)
    .setCcdEnabled(true).setCanSleep(false).setAdditionalMassProperties(mass,v([0,0,0]),v([mass,mass,mass]),{x:0,y:0,z:0,w:1}));}
  const a=body(0,masses[0]),b=body(-2,masses[1]);
  for(const rb of [a,b])world.createCollider(R.ColliderDesc.cuboid(.4,.3,.7).setDensity(0).setFriction(0).setRestitution(0),rb);
  let joint=world.createImpulseJoint(R.JointData.spherical(v([0,0,-1]),v([0,0,1])),a,b,true);
  joint.setContactsEnabled(contacts);world.step();const frames=[];
  for(let frame=0;frame<300;frame++){
   if(frame<100)a.applyImpulse(v([masses[0]*.002,0,-masses[0]*.01]),true);
   if(frame>=100&&frame<180)a.applyImpulse(v([-masses[0]*.001,0,masses[0]*.007]),true);
   if(frame===30)a.applyTorqueImpulse(v([0,masses[0]*.1,0]),true);
   if(frame===60)joint.setAnchor1(v([.1,.2,-1]));
   if(frame===120){world.removeImpulseJoint(joint,true);joint=null;}
   if(frame===150){joint=world.createImpulseJoint(R.JointData.spherical(v([.1,.2,-1]),v([0,0,1])),a,b,true);joint.setContactsEnabled(contacts);}
   world.step();frames.push({a:state(a),b:state(b),joint:joint!==null});
  }
  cases.push({masses,contacts,frames});world.free();
 }
 // Unlike the six disjoint trajectory cases, these boxes overlap while the
 // spherical joint starts at rest. Contacts are the only changed condition.
 const overlap=[];
 for(const contacts of[false,true]){
  const world=new R.World(v([0,0,0])),queue=new R.EventQueue(true);
  const bodies=[0,.5].map(x=>world.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(x,0,0)
   .setCcdEnabled(true).setCanSleep(false).setAdditionalMassProperties(1,v([0,0,0]),v([1,1,1]),{x:0,y:0,z:0,w:1})));
  const colliders=bodies.map(b=>world.createCollider(R.ColliderDesc.cuboid(.5,.5,.5).setDensity(0).setFriction(0).setRestitution(0)
   .setActiveEvents(R.ActiveEvents.CONTACT_FORCE_EVENTS),b));
  const joint=world.createImpulseJoint(R.JointData.spherical(v([.25,0,0]),v([-.25,0,0])),...bodies,true);joint.setContactsEnabled(contacts);
  const frames=[];
  for(let frame=0;frame<12;frame++){
   world.step(queue);const events=[];
   queue.drainContactForceEvents(event=>{
    const first=colliders.findIndex(c=>c.handle===event.collider1()),second=colliders.findIndex(c=>c.handle===event.collider2());
    assert(first>=0&&second>=0&&first!==second,'Unknown event endpoint');
    const xyz=a=>[a.x,a.y,a.z];events.push({first,second,force:xyz(event.totalForce()),magnitude:event.totalForceMagnitude(),
      maxDirection:xyz(event.maxForceDirection()),maxMagnitude:event.maxForceMagnitude()});
   });
   frames.push({a:state(bodies[0]),b:state(bodies[1]),events});
  }
  if(contacts){assert(frames.every(f=>f.events.length===1),'Enabled overlap did not produce force events');assert(Math.abs(frames[0].a[0])>.01,'Enabled overlap did not produce solver response');}
  else for(const f of frames){assert.equal(f.events.length,0);assert.deepEqual(f.a,[0,0,0,0,0,0,1,0,0,0,0,0,0]);assert.deepEqual(f.b,[.5,0,0,0,0,0,1,0,0,0,0,0,0]);}
  overlap.push({contacts,frames});queue.free();world.free();
 }
 // World queries use a step-maintained broadphase. The native bridge scans
 // current shapes at query time. Record both actual API boundaries explicitly;
 // never label a direct-collider query as an archived whole-world query.
 const parentWorld=new R.World(v([0,0,0]));
 const parent=parentWorld.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(2,3,4).setCcdEnabled(true).setCanSleep(false)
   .setAdditionalMassProperties(1,v([0,0,0]),v([1,1,1]),{x:0,y:0,z:0,w:1}));
 const shape=parentWorld.createCollider(R.ColliderDesc.cuboid(.4,.3,.6).setDensity(0).setFriction(0).setRestitution(0).setTranslation(0,.25,0),parent);
 const parentLocal=[];
 const xyz=a=>[a.x,a.y,a.z],xyzw=a=>[a.x,a.y,a.z,a.w];
 const hitValue=hit=>hit?{distance:hit.timeOfImpact,normal:xyz(hit.normal)}:null;
 function snapshot(operation){
  const raw=xyz(shape.translation());parentWorld.propagateModifiedBodyPositionsToColliders();
  const center=xyz(shape.translation()),rays=[];
  for(const direction of[[1,0,0],[0,-1,0],[0,0,1]]){
   const origin=center.map((x,i)=>x-5*direction[i]),ray=new R.Ray(v(origin),v(direction));
   const direct=hitValue(shape.castRayAndGetNormal(ray,10,true)),whole=hitValue(parentWorld.castRayAndGetNormal(ray,10,true));
   assert(direct,'Center ray missed its actual collider');
   rays.push({origin,direction,direct,whole,wholeMatchesCurrent:JSON.stringify(direct)===JSON.stringify(whole)});
  }
  parentLocal.push({operation,rawCollider:raw,collider:center,rotation:xyzw(shape.rotation()),local:xyz(shape.translationWrtParent()),body:state(parent),rays});
 }
 function apply(operation){
  if(operation.type==='step')parentWorld.step();
  else if(operation.type==='local'){
   const before=state(parent);shape.setTranslationWrtParent(v(operation.position));assert.deepEqual(state(parent),before,'Local setter changed body pose/momentum');
  }else if(operation.type==='pose'){
   parent.setTranslation(v(operation.position),true);parent.setRotation({x:operation.rotation[0],y:operation.rotation[1],z:operation.rotation[2],w:operation.rotation[3]},true);
  }else if(operation.type==='velocity'){
   parent.setLinvel(v(operation.linear),true);parent.setAngvel(v(operation.angular),true);
  }else throw Error('Unknown local-collider operation');
  snapshot(operation);
 }
 apply({type:'step',label:'initial-step'});
 apply({type:'local',position:[1,.5,-.75],label:'stationary-local-before-step'});
 assert.deepEqual(parentLocal[1].collider,parentLocal[0].collider,'Stationary local setter refreshed before step');
 apply({type:'step',label:'stationary-local-after-step'});
 assert.notDeepEqual(parentLocal[2].collider,parentLocal[1].collider,'Local setter did not refresh after step');
 apply({type:'local',position:[-.75,.1,.35],label:'second-local-before-step'});
 apply({type:'pose',position:[7,3,4],rotation:[0,0,0,1],label:'translated-parent-before-step'});
 apply({type:'step',label:'translated-parent-after-step'});
 apply({type:'local',position:[.6,.8,-.4],label:'third-local-before-step'});
 apply({type:'pose',position:[-3,4,2],rotation:[0,Math.SQRT1_2,0,Math.SQRT1_2],label:'rotated-parent-before-step'});
 apply({type:'step',label:'rotated-parent-after-step'});
 apply({type:'velocity',linear:[1.2,-.4,.5],angular:[.1,.3,-.2],label:'moving-parent-velocity'});
 apply({type:'local',position:[.15,-.2,.9],label:'moving-local-before-step'});
 for(let frame=0;frame<24;frame++){
  if(frame===5||frame===14)apply({type:'local',position:frame===5?[-.3,.7,.2]:[.8,-.1,-.6],label:`moving-local-${frame}-before-step`});
  apply({type:'step',label:`moving-parent-step-${frame}`});
 }
 const staleWorldRays=parentLocal.flatMap(row=>row.rays).filter(ray=>JSON.stringify(ray.direct)!==JSON.stringify(ray.whole)).length;
 assert(staleWorldRays>0,'Query timing fixture did not exercise the step-maintained broadphase distinction');
 parentWorld.free();
 const aloneWorld=new R.World(v([0,0,0])),alone=aloneWorld.createCollider(R.ColliderDesc.cuboid(.4,.3,.6).setTranslation(-8,3,4)),standalone=[];
 for(const label of['created','after-local-set','after-step']){
  if(label==='after-local-set')alone.setTranslationWrtParent(v([100,200,300]));
  if(label==='after-step')aloneWorld.step();
  aloneWorld.propagateModifiedBodyPositionsToColliders();
  const ray=new R.Ray(v([-13,3,4]),v([1,0,0]));
  standalone.push({label,collider:xyz(alone.translation()),rotation:xyzw(alone.rotation()),ray:hitValue(alone.castRayAndGetNormal(ray,10,true))});
 }
 assert(standalone.every(row=>JSON.stringify(row.collider)===JSON.stringify([-8,3,4])),'Standalone local setter did not remain a no-op');aloneWorld.free();
 const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
 const provenance={archivedFactory55077:sha(load.factories[55077].toString()),generator:sha(fs.readFileSync(__filename)),loader:sha(fs.readFileSync(path.join(__dirname,'../../smoke_vehicle_dynamics.js')))};
 const out=path.resolve(__dirname,'../../local-only/physics-fixtures/spherical-joints.json');fs.mkdirSync(path.dirname(out),{recursive:true});
 fs.writeFileSync(out,JSON.stringify({version:2,engine:R.version(),provenance,cases,overlap,parentLocal,standalone,staleWorldRays}),{mode:0o600});
 console.log(`PASS: recorded six disjoint joint trajectories, two real overlap/contact cases, ${parentLocal.length} parent-local checkpoints and standalone no-op; ${staleWorldRays} recorded stale whole-world rays`);
}
main().catch(e=>{console.error(e);process.exitCode=1});
