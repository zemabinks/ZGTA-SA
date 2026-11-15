#!/usr/bin/env node
// Collect original rail kinematics without fetching anything or running app UI.
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('./smoke_vehicle_dynamics');
async function main(){
  const load=archivedModules(),R=load(55077);await R.init();const T=load(85339),trains=load(91584);
  load.e=async id=>{if(id!==1873)throw Error('Unexpected dynamic module '+id)};
  load.t=id=>({default:load(id)});await trains.fX();
  const all=JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/site/game/native/vehicles.physics.json'),'utf8')).models;
  const scenarios=[
    {name:'freight-accelerate',model:537,steps:1800,input:()=>({throttle:1})},
    {name:'streak-brake',model:538,steps:1800,input:i=>({throttle:i<900?1:-1})},
    {name:'tram-reverse',model:449,steps:1800,input:i=>({throttle:i<600?-1:i<1200?0:1})},
    {name:'freight-handbrake',model:537,steps:1800,input:i=>({throttle:1,handbrake:i>=900})},
    {name:'carriage-backwards',model:569,opposite:true,steps:1200,input:()=>({throttle:1})},
    {name:'freightbox-coast',model:590,steps:1200,input:i=>({throttle:i<600?1:0})},
    {name:'streakcar-reverse',model:570,steps:1200,input:()=>({throttle:-1})},
  ];
  const vector=v=>[v.x,v.y,v.z],quaternion=q=>[q.x,q.y,q.z,q.w],cases=[];
  for(const scenario of scenarios){
    const config=all[scenario.model],line=scenario.model===449?trains.ZF().find(x=>x.tram):trains.ZF()[0];
    const start=37%line.count,position=new T.Pq0().fromArray(line.points,start*3),nearest=trains.VO(config.id,position);
    const heading=Math.atan2(-nearest.way.x,-nearest.way.z)+(scenario.opposite?Math.PI:0);
    const world=new R.World({x:0,y:-18,z:0}),built={...config,id:String(config.id),wheels:config.wheels.map(w=>({...w,centre:new T.Pq0(...w.centre)}))};
    const car=trains.J6({RAPIER:R,world},built,config.id,327663,position,heading);if(!car)throw Error('Original train constructor failed');
    let translated,rotated,linearVelocity,angularVelocity;
    const transform=car.rigid.setTranslation.bind(car.rigid),rotate=car.rigid.setRotation.bind(car.rigid),linear=car.rigid.setLinvel.bind(car.rigid),angular=car.rigid.setAngvel.bind(car.rigid);
    car.rigid.setTranslation=(v,wake)=>{translated=vector(v);transform(v,wake)};car.rigid.setRotation=(q,wake)=>{rotated=quaternion(q);rotate(q,wake)};
    car.rigid.setLinvel=(v,wake)=>{linearVelocity=vector(v);linear(v,wake)};car.rigid.setAngvel=(v,wake)=>{angularVelocity=vector(v);angular(v,wake)};
    const carriageConfigs=(trains.Wm[config.id]||[]).map(id=>({...all[id],id:String(id)})),carriageCache={};
    const initial={position:vector(car.rigid.translation()),rotation:quaternion(car.rigid.rotation())},frames=[];
    world.step();
    for(let index=0;index<scenario.steps;index++){
      const body={position:vector(car.rigid.translation()),rotation:quaternion(car.rigid.rotation()),linearVelocity:vector(car.rigid.linvel()),angularVelocity:vector(car.rigid.angvel())};
      const carriages=[];trains.wY(built,new T.Pq0(...body.position),new T.PTz(...body.rotation),carriageConfigs,(index,position,rotation)=>{carriages[index]={position:vector(position),rotation:quaternion(rotation)}},carriageCache);
      const input=scenario.input(index);car.step(1/60,input);
      frames.push({body,input,position:translated,rotation:rotated,linearVelocity,angularVelocity,speed:car.speed,carriages});world.step();
    }
    cases.push({name:scenario.name,config,carriageConfigs,start:vector(position),heading,initial,frames,final:vector(car.rigid.translation())});world.free();console.log(scenario.name,frames.length);
  }
  fs.writeFileSync(path.join(__dirname,'local-only/physics-fixtures/train-dynamics.json'),JSON.stringify({version:1,lines:trains.ZF().map(l=>({tram:l.tram,points:[...l.points],from:[...l.from],total:l.total})),cases}),{mode:0o600});
  console.log('PASS original train references saved locally');
}
main().catch(error=>{console.error(error);process.exitCode=1});
