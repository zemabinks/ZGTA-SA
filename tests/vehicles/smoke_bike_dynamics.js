#!/usr/bin/env node
// Original motorcycle/bicycle reference traces. Requires locally archived
// public code and the exact DFF-derived vehicles.physics.json metadata.
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('./smoke_vehicle_dynamics');
async function main(){
  const load=archivedModules(),R=load(55077);await R.init();const T=load(85339);
  const metadata=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/vehicles.physics.json'),'utf8')).models;
  const scenarios=[
    {name:'motorcycle-straight',model:461,steps:600,input:i=>({throttle:i<60?0:1,steer:0})},
    {name:'motorcycle-turn',model:461,steps:600,input:i=>({throttle:i<60?0:1,steer:i<240?0:0.5})},
    {name:'motorcycle-brake',model:461,steps:600,input:i=>({throttle:i<60?0:i<360?1:-1,steer:0})},
    {name:'motorcycle-reverse',model:461,steps:420,input:i=>({throttle:i<60?0:-1,steer:0})},
    {name:'motorcycle-wheelie',model:468,steps:600,input:i=>({throttle:i<60?0:1,steer:0,lean:i<120?0:-1})},
    {name:'motorcycle-stoppie',model:468,steps:600,input:i=>({throttle:i<60?0:i<360?1:-1,steer:0,lean:i<360?0:1})},
    {name:'motorcycle-handbrake',model:522,steps:600,input:i=>({throttle:i<60?0:1,steer:i<240?0:0.5,handbrake:i>=240&&i<360})},
    {name:'motorcycle-wet',model:522,steps:600,input:i=>({throttle:i<60?0:1,steer:i<240?0:0.5,wetness:0.8})},
    {name:'motorcycle-burst',model:461,tyres:[1,0],steps:480,input:i=>({throttle:i<60?0:1,steer:0})},
    {name:'motorcycle-airborne',model:468,height:12,steps:300,input:()=>({throttle:0,steer:0.6,lean:-0.7})},
    {name:'motorcycle-riderless',model:461,steps:480,input:i=>({throttle:i<120?1:0,steer:0,riderless:i>=120})},
    {name:'bicycle-straight',model:481,steps:600,input:i=>({throttle:i<60?0:1,steer:0})},
    {name:'bicycle-turn',model:510,steps:600,input:i=>({throttle:i<60?0:1,steer:i<240?0:0.4})},
    {name:'bicycle-hop',model:481,steps:600,input:i=>({throttle:i<60?0:1,steer:0,hop:i>=180&&i<210})},
    {name:'bicycle-tap',model:509,steps:600,input:i=>({throttle:i>=60&&(Math.floor(i/12)%2===0)?1:0,steer:0})},
  ];
  const cases=[];
  for(const scenario of scenarios){
    const config=metadata[scenario.model];if(!config?.hubs||!config?.bike)throw Error('Prepare bike metadata '+scenario.model);
    const world=new R.World({x:0,y:-9.81,z:0});world.createCollider(R.ColliderDesc.cuboid(1000,.1,1000).setTranslation(0,-.1,0));
    const built={...config,id:String(config.id),nitro:0,hydraulics:false,wheels:config.wheels.map(w=>({...w,centre:new T.Pq0(...w.centre)}))};
    const car=(config.pedalled?load(40405).u:load(78338).o)({RAPIER:R,world,waterLevel:()=>null},built,config.id);
    car.rigid.setTranslation({x:0,y:scenario.height??0.02,z:0},true);car.setTyres(scenario.tyres??[]);
    let queries=[],requestedLinear,requestedAngular;const cast=world.castRayAndGetNormal.bind(world);
    world.castRayAndGetNormal=(...args)=>{const hit=cast(...args);queries.push(hit?{distance:hit.timeOfImpact,normal:[hit.normal.x,hit.normal.y,hit.normal.z],surface:2,material:-1}:null);return hit};
    const lin=car.rigid.setLinvel.bind(car.rigid),ang=car.rigid.setAngvel.bind(car.rigid);
    car.rigid.setLinvel=(v,wake)=>{requestedLinear=[v.x,v.y,v.z];lin(v,wake)};car.rigid.setAngvel=(v,wake)=>{requestedAngular=[v.x,v.y,v.z];ang(v,wake)};
    world.step();const frames=[];
    for(let i=0;i<scenario.steps;i++){
      const p=car.rigid.translation(),q=car.rigid.rotation(),v=car.rigid.linvel(),a=car.rigid.angvel();
      const body={position:[p.x,p.y,p.z],rotation:[q.x,q.y,q.z,q.w],linearVelocity:[v.x,v.y,v.z],angularVelocity:[a.x,a.y,a.z]};
      queries=[];const input=scenario.input(i);load(74348).Ig.value=input.wetness??0;car.step(1/60,input);
      frames.push({body,input,rays:queries,linearVelocity:requestedLinear,angularVelocity:requestedAngular,
        steering:car.steer,gear:car.gear,gas:car.gas,burnout:car.burnout,lean:car.lean,drop:[...car.drop],
        rearSpin:car.rearSpin,pedal:car.pedal??0,crank:car.crank??0,
        wheels:car.lines.map(w=>({index:w.index,compression:w.compression,counts:w.counts,state:w.state,spin:(w.spin??0)*50,point:[w.point.x,w.point.y,w.point.z],normal:[w.normal.x,w.normal.y,w.normal.z]}))});
      world.step();
    }
    const p=car.rigid.translation();cases.push({name:scenario.name,initialHeight:scenario.height??0.02,config,tyres:scenario.tyres??[],frames,final:[p.x,p.y,p.z]});world.free();
    console.log(scenario.name,frames.length,cases.at(-1).final);
  }
  const output=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/physics-fixtures/bike-dynamics.json');
  fs.writeFileSync(output,JSON.stringify({version:1,source:'Original archived78338+40405 and original Rapier WASM',delta:1/60,cases}),{mode:0o600});
  console.log('PASS original motorcycle/bicycle traces saved locally');
}
main().catch(e=>{console.error(e);process.exitCode=1});
