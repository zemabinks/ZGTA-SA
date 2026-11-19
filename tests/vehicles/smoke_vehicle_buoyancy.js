#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('./smoke_vehicle_dynamics');
async function main(){
  const load=archivedModules(),R=load(55077);await R.init();const T=load(85339);
  const all=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/vehicles.physics.json'),'utf8')).models;
  const scenarios=[
    {name:'speedboat-accelerate',model:446,steps:720,input:()=>({throttle:1,steer:0})},
    {name:'speedboat-turn',model:452,steps:720,input:i=>({throttle:1,steer:i<240?0:0.6})},
    {name:'speedboat-reverse',model:493,steps:720,input:i=>({throttle:i<360?1:-1,steer:0.3})},
    {name:'dinghy-brake',model:473,steps:720,input:i=>({throttle:1,steer:0.3,handbrake:i>=360})},
    {name:'sailboat-waves',model:484,waves:true,steps:720,input:()=>({throttle:0.5,steer:0.4})},
    {name:'seaplane-water',model:460,waves:true,steps:720,input:i=>({throttle:i<480?1:0,pitch:i<300?0:0.15,steer:0.2})},
    {name:'hover-water',model:539,waves:true,steps:720,input:()=>({throttle:0.6,steer:0.4,roll:0.1})},
    {name:'car-sinking',model:420,steps:1200,input:()=>({throttle:0,steer:0})},
    {name:'car-leave-water',model:411,steps:720,water:i=>i<480?0:null,input:()=>({throttle:1,steer:0})},
  ];
  const cases=[],vector=v=>[v.x,v.y,v.z];
  for(const scenario of scenarios){
    const config=all[scenario.model],world=new R.World({x:0,y:-18,z:0});
    const convert=w=>({...w,centre:new T.Pq0(...w.centre)});
    const built={...config,id:String(config.id),nitro:0,hydraulics:false,wheels:config.wheels.map(convert),...(config.struts?{struts:config.struts.map(convert)}:{})};
    let tick=0,levels=[],waves=[],allLevels=[],allWaves=[],rays=[],linearVelocity,angularVelocity;
    const environment={RAPIER:R,world,waterLevel:p=>{const level=scenario.water?.(tick)??(scenario.water?null:0),row={point:vector(p),level};levels.push(row);allLevels.push(row);return level}};
    if(scenario.waves)environment.sea={rise:(x,y,normal)=>{
      const height=.08*Math.sin(x*.2+tick*.03)+.04*Math.cos(y*.3-tick*.02);
      const n=new T.Pq0(-.016*Math.cos(x*.2+tick*.03),1,-.012*Math.sin(y*.3-tick*.02)).normalize();
      if(normal)normal.copy(n);const row={height,normal:vector(n)};waves.push(row);allWaves.push(row);return height;
    }};
    const car=load(23895).Xn(environment,built,config.id);car.rigid.setTranslation({x:0,y:-.5,z:0},true);
    const cast=world.castRayAndGetNormal.bind(world),linear=car.rigid.setLinvel.bind(car.rigid),angular=car.rigid.setAngvel.bind(car.rigid);
    world.castRayAndGetNormal=(...args)=>{const hit=cast(...args);rays.push(hit?{distance:hit.timeOfImpact,normal:vector(hit.normal),surface:2,material:-1}:null);return hit};
    car.rigid.setLinvel=(v,wake)=>{linearVelocity=vector(v);linear(v,wake)};car.rigid.setAngvel=(v,wake)=>{angularVelocity=vector(v);angular(v,wake)};
    const original=car.afloat.step.bind(car.afloat),frames=[];let captured;
    car.afloat.step=(body,input,step,wheels)=>{
      levels=[];waves=[];
      captured={input:{...input},step,wheels,body:{move:vector(body.move),turn:vector(body.turn),right:vector(body.right),forward:vector(body.forward),
        up:vector(body.up),middle:vector(body.middle),place:vector(body.place),quaternion:[body.quaternion.x,body.quaternion.y,body.quaternion.z,body.quaternion.w],mass:car.mass,turnMass:body.turnMass,wheels:body.wheels}};
      original(body,input,step,wheels);
      const water=car.afloat;
      captured.expected={move:vector(body.move),turn:vector(body.turn),touching:water.touching,onWater:water.onWater,lost:water.lost,
        dead:water.dead,rudder:water.rudder,gas:water.gas,propeller:water.propeller,wake:water.wake,immersion:water.immersion,slam:water.takeSlam()};
      captured.levels=[...levels];captured.waves=[...waves];
    };
    world.step();
    for(tick=0;tick<scenario.steps;tick++){
      const p=car.rigid.translation(),q=car.rigid.rotation(),v=car.rigid.linvel(),a=car.rigid.angvel();
      const body={position:vector(p),rotation:[q.x,q.y,q.z,q.w],linearVelocity:vector(v),angularVelocity:vector(a)};
      allLevels=[];allWaves=[];rays=[];car.step(1/60,scenario.input(tick));
      captured.full={body,rays,levels:allLevels,waves:allWaves,linearVelocity,angularVelocity,steering:car.steer,gear:car.gear,gas:car.gas,burnout:car.burnout,
        wheels:car.lines.map(w=>({index:w.index,compression:w.compression,offset:w.offset,counts:w.counts,state:w.state,spin:(w.spin??0)*50,point:vector(w.point),normal:vector(w.normal)}))};
      frames.push(captured);world.step();
    }
    cases.push({name:scenario.name,config,waves:!!scenario.waves,frames,final:vector(car.rigid.translation())});world.free();console.log(scenario.name,frames.length);
  }
  fs.writeFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/physics-fixtures/vehicle-buoyancy.json'),JSON.stringify({version:1,cases}),{mode:0o600});
  console.log('PASS original boat/seaplane/car buoyancy contexts saved locally');
}
main().catch(error=>{console.error(error);process.exitCode=1});
