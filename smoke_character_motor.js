#!/usr/bin/env node
// Run the original on-foot motor and Rapier offline. Only measurements are
// saved under ignored local-only/, never raw browser code or game assets.
const fs = require('node:fs');
const path = require('node:path');
const {archivedModules} = require('./smoke_vehicle_dynamics');

async function main() {
  const load = archivedModules(), R = load(55077), T = load(85339);
  await R.init();
  const factory = load(39943), cases = [];
  const scenarios = [
    {name:'walk_wall',steps:360,start:[0,1.72,0],wall:true,input:()=>({travel:[0.04,0,0]})},
    {name:'jump_ceiling',steps:240,start:[0,1.72,0],ceiling:true,input:i=>({travel:[0,0,-0.02],jump:i===45?6.07:0})},
    {name:'stairs',steps:300,start:[0,1.72,0],stairs:true,input:()=>({travel:[0,0,-0.04]})},
    {name:'slope',steps:300,start:[0,1.72,2],slope:true,input:()=>({travel:[0,0,-0.04]})},
    {name:'slippery',steps:300,start:[0,1.72,2],slope:true,material:17,input:()=>({travel:[0,0,-0.04]})},
    {name:'fall',steps:180,start:[0,9,0],input:()=>({travel:[0,0,0]})},
    {name:'vehicle_contact',steps:240,start:[0,1.72,0],vehicle:true,input:()=>({travel:[0.04,0,0]})},
    {name:'vertical_override',steps:180,start:[0,3,0],input:i=>({travel:[0,0,0.01],vertical:i<90?-2:0,held:i>=90})},
  ];
  const vector = v => [v.x,v.y,v.z];
  for (const scenario of scenarios) {
    const world = new R.World({x:0,y:-9.81,z:0}), materials = new Map(), others = new Set();
    const ids = new Map(), scene = [], sceneBodies = new Map(); let nextID = 1, record = null;
    const id = handle => { if (!ids.has(handle)) ids.set(handle,nextID++); return ids.get(handle); };
    function collider(value) {
      const body = value.parent();
      return {id:id(value.handle),body:body?id('body:'+body.handle):null,dynamic:!!body?.isDynamic(),
        translation:vector(value.translation()),material:materials.get(value.handle)??-1};
    }
    function hit(value) { return value?{collider:collider(value.collider),distance:value.timeOfImpact??value.time_of_impact??value.toi,
      normal:value.normal?vector(value.normal):[0,0,0]}:null; }
    function box(half,at,material=0,rotation=null,body=null) {
      const desc=R.ColliderDesc.cuboid(...half).setTranslation(...at).setCollisionGroups(131071);
      if(rotation)desc.setRotation(rotation);
      const result=world.createCollider(desc,body);id(result.handle);materials.set(result.handle,material);
      if(body)sceneBodies.set(id('body:'+body.handle),body);
      scene.push({id:id(result.handle),kind:'box',half,at,material,rotation:rotation?[rotation.x,rotation.y,rotation.z,rotation.w]:[0,0,0,1],
        groups:131071,solverGroups:0xffffffff,body:body?{id:id('body:'+body.handle),kind:'dynamic',
          position:vector(body.translation()),rotation:[0,0,0,1],gravityScale:1,density:1}:null});
      return result;
    }
    box([30,.1,30],[0,-.1,0]);
    if(scenario.wall)box([.2,2,10],[3,2,0]);
    if(scenario.ceiling)box([4,.1,4],[0,2.65,-1]);
    if(scenario.stairs)for(let i=0;i<5;i++)box([2,(i+1)*.1,.4],[0,(i+1)*.1,-2-i*.8]);
    if(scenario.slope) {const a=-25*Math.PI/180;box([3,.2,4],[0,1.2,-4],scenario.material??0,{x:Math.sin(a/2),y:0,z:0,w:Math.cos(a/2)});}
    if(scenario.vehicle){const b=world.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(2,.65,0));
      const c=box([.55,.6,1],[0,0,0],63,null,b);others.add(c.handle);}
    world.step();
    for(const shape of scene)if(shape.body){
      const body=sceneBodies.get(shape.body.id),q=body.principalInertiaLocalFrame();
      Object.assign(shape.body,{mass:body.mass(),localCom:vector(body.localCom()),inertia:vector(body.principalInertia()),
        inertiaFrame:[q.x,q.y,q.z,q.w],afterInitialStep:{position:vector(body.translation()),velocity:vector(body.linvel())}});
    }
    const initialIds = {walker:nextID,probe:nextID+1};
    const create = world.createCollider.bind(world);
    world.createCollider=(...args)=>{const c=create(...args);id(c.handle);return c;};
    const motor=factory.jE({RAPIER:R,world,others,materials});motor.setActive(true);
    const originalIntersections=world.intersectionsWithShape.bind(world);
    world.intersectionsWithShape=(position,rotation,shape,callback,...args)=>{
      const row={center:vector(position),halfHeight:shape.halfHeight,radius:shape.radius,hits:[]};
      if(record)record.intersections.push(row);
      return originalIntersections(position,rotation,shape,c=>{row.hits.push(collider(c));return callback(c);},...args);
    };
    const originalRay=world.castRayAndGetNormal.bind(world);
    world.castRayAndGetNormal=(ray,distance,...args)=>{const value=originalRay(ray,distance,...args);
      if(record)record.rays.push({origin:vector(ray.origin),distance,groups:args[2],hit:hit(value)});return value;};
    const originalShape=world.castShape.bind(world);
    world.castShape=(position,rotation,direction,shape,targetDistance,distance,...args)=>{
      const value=originalShape(position,rotation,direction,shape,targetDistance,distance,...args);
      if(record)record.casts.push({origin:vector(position),radius:shape.radius,distance,groups:args[2],hit:hit(value)});return value;
    };
    // All query contacts are requested on the main walker. Patch prototypes so
    // wrappers remain valid when Rapier returns a new JS collider handle object.
    const cp=R.Collider.prototype, oldContact=cp.contactCollider,oldProject=cp.projectPoint;
    cp.contactCollider=function(other,prediction){const v=oldContact.call(this,other,prediction);
      if(record)record.contacts.push({first:id(this.handle),second:id(other.handle),prediction,
        hit:v?{distance:v.distance,normal2:vector(v.normal2),point1:vector(v.point1),point2:vector(v.point2)}:null});return v;};
    cp.projectPoint=function(point,solid){const value=oldProject.call(this,point,solid);
      if(record)record.projects.push({collider:id(this.handle),point:vector(point),hit:value?vector(value.point):null});return value;};
    // The original creates exactly one KCC; it can be observed through the
    // world-owned controller collection without changing movement behavior.
    const controllers=[];
    // Find its public world-owned controller by wrapping the factory on a
    // second motor, then dispose the first to retain original IDs explicitly.
    motor.dispose();
    const makeController=world.createCharacterController.bind(world);
    world.createCharacterController=(...args)=>{const p=makeController(...args);controllers.push(p);return p;};
    const active=factory.jE({RAPIER:R,world,others,materials});active.setActive(true);
    const walker=nextID-2,probe=nextID-1;
    const controller=controllers[0],compute=controller.computeColliderMovement.bind(controller);
    controller.computeColliderMovement=(c,desired,...args)=>{compute(c,desired,...args);
      const normals=[];for(let i=0;i<controller.numComputedCollisions();i++)normals.push(vector(controller.computedCollision(i).normal1));
      if(record)record.moves.push({center:vector(c.translation()),desired:vector(desired),
        translation:vector(controller.computedMovement()),normals});};
    const position=new T.Pq0(...scenario.start),frames=[];
    for(let frame=0;frame<scenario.steps;frame++){
      record={intersections:[],rays:[],casts:[],contacts:[],projects:[],moves:[]};
      const input=scenario.input(frame),before=vector(position);
      active.step(position,new T.Pq0(...input.travel),input.jump??0,1/60,input.held??false,input.vertical??null);
      const expected={position:vector(position),grounded:active.grounded,rising:active.rising,propped:active.propped,
        easing:active.eased(),barred:[0,Math.PI/2,Math.PI,Math.PI*1.5].map(a=>active.barred(a)),
        pressed:active.pressed.map(v=>({body:id('body:'+v.body),direction:[v.x,v.z],point:vector(v.at),speed:v.speed}))};
      frames.push({before,input,queries:record,expected});record=null;world.step();
    }
    cp.contactCollider=oldContact;cp.projectPoint=oldProject;
    cases.push({name:scenario.name,scene,walker,probe,others:[...others].map(id),frames});
    active.dispose();world.free();console.log(scenario.name,frames.length,'frames',frames.at(-1).expected.position);
  }
  const destination=path.join(__dirname,'local-only/physics-fixtures');fs.mkdirSync(destination,{recursive:true});
  fs.writeFileSync(path.join(destination,'character-motor.json'),JSON.stringify({version:1,delta:1/60,cases}),{mode:0o600});
  console.log('PASS: actual archived on-foot motor reference measurements saved locally');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
