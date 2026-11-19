#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('./smoke_vehicle_dynamics');
async function main(){
  const load=archivedModules(),R=load(55077);await R.init();const T=load(85339);
  const all=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/vehicles.physics.json'),'utf8')).models;
  const scenarios=[
    {name:'plane-takeoff',model:593,steps:900,input:i=>({throttle:1,pitch:i<240?0:0.3,roll:0,yaw:0})},
    {name:'plane-banking',model:513,steps:720,input:i=>({throttle:1,pitch:0.2,roll:i<240?0:0.5,yaw:i<360?0:-0.3})},
    {name:'plane-gear',model:519,steps:720,gear:i=>i>=240,input:i=>({throttle:1,pitch:i<180?0:0.2,roll:0,yaw:0})},
    {name:'plane-reverse',model:464,steps:360,input:()=>({throttle:-1,pitch:0,roll:0,yaw:0})},
    {name:'plane-abandoned',model:511,steps:600,input:i=>({throttle:1,pitch:0.1,roll:0.2,yaw:0,nobody:i>=300})},
    {name:'helicopter-lift',model:487,steps:720,input:()=>({throttle:1,pitch:0,roll:0,yaw:0})},
    {name:'helicopter-controls',model:425,steps:900,input:i=>({throttle:0.6,pitch:i<300?0:0.3,roll:i<480?0:0.4,yaw:i<600?0:-0.5})},
    {name:'helicopter-abandoned',model:469,steps:600,input:i=>({throttle:1,pitch:0.2,roll:0,yaw:0.2,nobody:i>=300})},
    {name:'hydra-transition',model:520,steps:1200,input:i=>({throttle:1,pitch:i<600?0:0.2,roll:i<900?0:0.3,yaw:0,jets:i>=360&&i<660?-1:0})},
    {name:'hydra-abandoned',model:520,steps:600,input:i=>({throttle:0.6,pitch:0.2,roll:-0.2,yaw:0.4,nobody:i>=300})},
    {name:'vortex-hover',model:539,steps:720,input:i=>({throttle:i<480?1:-1,pitch:0.2,roll:0.3,yaw:0.2})},
  ];
  const cases=[];
  for(const scenario of scenarios){
    const config=all[scenario.model];if(!config.flying)throw Error('Prepare flight metadata '+scenario.model);
    const world=new R.World({x:0,y:-18,z:0});world.createCollider(R.ColliderDesc.cuboid(10000,.1,10000).setTranslation(0,-.1,0));
    const convert=w=>({...w,centre:new T.Pq0(...w.centre)});
    const built={...config,id:String(config.id),nitro:0,hydraulics:false,wheels:config.wheels.map(convert),struts:config.struts.map(convert)};
    const car=load(23895).Xn({RAPIER:R,world,waterLevel:()=>null},built,config.id);
    car.rigid.setTranslation({x:0,y:10,z:0},true);
    let rays=[],linearVelocity,angularVelocity;
    const cast=world.castRayAndGetNormal.bind(world),linear=car.rigid.setLinvel.bind(car.rigid),angular=car.rigid.setAngvel.bind(car.rigid);
    world.castRayAndGetNormal=(...args)=>{const hit=cast(...args);rays.push(hit?{distance:hit.timeOfImpact,normal:[hit.normal.x,hit.normal.y,hit.normal.z],surface:2,material:-1}:null);return hit};
    car.rigid.setLinvel=(v,wake)=>{linearVelocity=[v.x,v.y,v.z];linear(v,wake)};car.rigid.setAngvel=(v,wake)=>{angularVelocity=[v.x,v.y,v.z];angular(v,wake)};
    const flight=car.flight,original=flight.step.bind(flight),frames=[];
    let captured;
    const vector=v=>[v.x,v.y,v.z];
    flight.step=(body,input,step)=>{
      captured={input:{...input},step,body:{move:vector(body.move),turn:vector(body.turn),right:vector(body.right),
        forward:vector(body.forward),up:vector(body.up),middle:vector(body.middle),place:vector(body.place),
        quaternion:[body.quaternion.x,body.quaternion.y,body.quaternion.z,body.quaternion.w],mass:car.mass,turnMass:body.turnMass,wheels:body.wheels}};
      original(body,input,step);
      captured.expected={move:vector(body.move),turn:vector(body.turn),rotor:flight.rotor,turning:flight.turning,
        nozzle:flight.nozzle,throttle:flight.throttle,drag:flight.drag,gearUp:flight.gearUp};
    };
    world.step();
    for(let index=0;index<scenario.steps;index++){
      const gear=scenario.gear?.(index)??false;flight.setGear(gear);
      const p=car.rigid.translation(),q=car.rigid.rotation(),v=car.rigid.linvel(),a=car.rigid.angvel();
      const body={position:vector(p),rotation:[q.x,q.y,q.z,q.w],linearVelocity:vector(v),angularVelocity:vector(a)};
      rays=[];car.step(1/60,scenario.input(index));
      const full={body,rays,linearVelocity,angularVelocity,steering:car.steer,gear:car.gear,gas:car.gas,burnout:car.burnout,
        wheels:car.lines.map(w=>({index:w.index,compression:w.compression,offset:w.offset,counts:w.counts,state:w.state,spin:(w.spin??0)*50,point:vector(w.point),normal:vector(w.normal)}))};
      frames.push({...captured,gear,full});world.step();
    }
    cases.push({name:scenario.name,config,frames,final:vector(car.rigid.translation())});world.free();console.log(scenario.name,frames.length);
  }
  fs.writeFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/physics-fixtures/flight-dynamics.json'),JSON.stringify({version:1,cases}),{mode:0o600});
  console.log('PASS original plane/helicopter/VTOL force contexts saved locally');
}
main().catch(error=>{console.error(error);process.exitCode=1});
