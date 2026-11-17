#!/usr/bin/env node
// Replay the actual public19737 parked manager in an offline VM. Original
// game assets and numerical reference frames remain in ignored local-only/.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {createLibrary}=require('./prepare_native_vehicle_rigs');
function managerFactory(lib){
 const load=lib.load,d=lib.T,source=load.factories[19737].toString(),clock={value:0,now(){return this.value}};
 const modules={};for(const match of source.matchAll(/\b([A-Za-z_$][\w$]*)=l\((\d+(?:e\d+)?)\)/g))modules[match[1]]=Number(match[2]);
 const values={d,performance:clock,console,Math:Object.assign(Object.create(Math),{random:()=>.37}),Number,String,Set,Map,WeakMap,Array,Boolean,Object,Infinity,Symbol};
 const scope=new Proxy(values,{has:()=>true,get(target,key){if(key===Symbol.unscopables)return undefined;if(key in target)return target[key];if(key in modules)return target[key]=load(modules[key]);throw Error('Unprovided source dependency '+String(key));}});
 const start=source.indexOf('cq=function')+3,marker='for(let e of[...ec])ep(e)}}',end=source.indexOf(marker,start)+marker.length+1;
 assert(start>=3&&end>start,'Original19737 manager signature');
 const helpers=source.slice(source.indexOf('let vV=new d.Pq0'),source.indexOf(',kf={16:9'));
 const workStart=source.indexOf('let vn='),workEnd=source.indexOf('var vm=',workStart);
 assert(workStart>=0&&workEnd>workStart,'Original work-angle helper signature');
 const muStart=source.indexOf('function mu(e)'),muEnd=source.indexOf('let md=',muStart);
 const expression=source.slice(start,end).replace('return{recar(e,t)', 'return{native:()=>({N,G,B,ek,eI,ea,el,Q}),recar(e,t)');
 const make=Function('scope','with(scope){'+helpers+';const mi=(e,t)=>{let l=e.root.userData.frames.get(t);return l?new d.Pq0().setFromMatrixPosition(l):null},ms=(e,t)=>new d.Pq0(t.x,e.origin+t.z,-t.y);'+source.slice(workStart,workEnd)+source.slice(muStart,muEnd)+';return ('+expression+')}')(scope);
 return {make,clock};
}
async function main(){
 const lib=createLibrary(),load=lib.load,R=load(55077);await R.init();const T=lib.T,{make,clock}=managerFactory(lib);
 const models=JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/site/game/native/vehicles.physics.json'))).models;
 const vec=v=>[v.x,v.y,v.z],quat=q=>[q.x,q.y,q.z,q.w],cases=[];
 for(const scenario of [
  {name:'spawned-manana',model:410,steps:240,height:1.1,align:true,pool:true},
  {name:'drop-taxi',model:420,steps:360,height:3.5},
  {name:'rolling-taxi',model:420,steps:480,height:1.1,linear:[2.4,0,-8]},
  {name:'fallen-motorbike',model:522,steps:360,height:1.1,roll:.9},
  {name:'parked-bicycle',model:481,steps:360,height:1.1},
  {name:'pedestrian-shove',model:410,steps:420,height:1.1,shove:true},
  {name:'rest-demotion',model:420,steps:480,height:1.1,farAfter:120,align:true,pool:true},
  {name:'slope-alignment',model:410,steps:360,height:1.1,floorRoll:.08,align:true,pool:true},
  {name:'press-promotion',model:410,steps:420,height:1.1,align:true,pool:true,deferPromotion:true,shove:true},
 ]){
  const world=new R.World({x:0,y:-18,z:0}),floorRotation=new T.PTz().setFromAxisAngle(new T.Pq0(0,0,1),scenario.floorRoll??0);
  world.createCollider(R.ColliderDesc.cuboid(1000,.1,1000).setTranslation(0,-.1,0).setRotation(floorRotation).setFriction(.8).setCollisionGroups(131071));
  // Bring the query scene current before creating vehicle bodies, exactly as
  // a loaded browser collision cell exists before promotion.
  world.step();clock.value=0;
  const environment={RAPIER:R,world,others:new Set,waterLevel:()=>null,below:(at,distance)=>world.castRay(new R.Ray(at,{x:0,y:-1,z:0}),distance,true,undefined,0xffff0001)?.timeOfImpact??null};
  const packets=[],manager=make({scene:new T.YJl(),onMove:(id,state)=>packets.push({id,state})});manager.setPhysics(environment);
  const raw=models[scenario.model],scene=lib.build(scenario.model),built={...raw,...scene,id:String(scenario.model),bounds:raw.bounds,origin:raw.origin,kind:raw.kind,body:scene.body,root:scene.root,wheels:scene.wheels,dispose(){},setLights(){}};
  const group=new T.YJl();group.position.set(0,Math.fround(scenario.height),0);group.quaternion.setFromEuler(new T.O9p(0,0,scenario.roll??0,'YXZ'));group.add(built.body);
  const entry={id:'test',group,built,driver:null,health:1000,damage:'',work:0,solids:[],rig:null,body:null,alive:true,target:{position:group.position.clone(),quaternion:group.quaternion.clone()},eased:true,wreck:load(39851).k(built),doors:load(66242)._E(built.table,built.bounds,built.table.modelFlags,scenario.model),held:new Map,asked:1};
  const api=manager.native();api.N.set(entry.id,entry);
  if(scenario.align)api.ek(group.position,group.quaternion,0,null);
  entry.target={position:group.position.clone(),quaternion:group.quaternion.clone()};
  const initial={position:vec(group.position),rotation:quat(group.quaternion),linearVelocity:scenario.linear??[0,0,0]};
  if(scenario.deferPromotion)api.B(entry);else api.G(entry,scenario.linear?new T.Pq0(...scenario.linear):null);
  const frames=[];
  for(let i=0;i<scenario.steps;i++){
   clock.value=i*1000/60;const near=scenario.deferPromotion?null:i<(scenario.farAfter??Infinity)?new T.Pq0(0,0,3):new T.Pq0(150,0,3);
   manager.update(clock.value,1/60,near);
   let press=null;
   if(scenario.shove&&i>=100&&i<160){const at=(entry.rig?.rigid??entry.body).translation();press={direction:[1,0],point:[at.x+.5,at.y+.5,at.z],speed:1.4};manager.shove([{body:(entry.rig?.rigid??entry.body).handle,x:1,z:0,at:{x:press.point[0],y:press.point[1],z:press.point[2]},speed:press.speed}]);}
   manager.beforeStep(1/60);world.step();manager.afterStep(1/60);
   const body=entry.rig?.rigid??entry.body;
   frames.push({near:near?vec(near):null,press,dynamic:!!entry.rig,position:vec(body.translation()),rotation:quat(body.rotation()),linearVelocity:vec(body.linvel()),angularVelocity:vec(body.angvel()),health:entry.health,damage:entry.damage,frontSpin:entry.rolled??0,rearSpin:entry.rearRolled??0,packets:packets.splice(0)});
  }
  cases.push({...scenario,initial,frames});manager.dispose();world.free();console.log(scenario.name,frames.length,frames.at(-1).position,'hp',frames.at(-1).health);
 }
 fs.writeFileSync(path.join(__dirname,'local-only/physics-fixtures/unattended-vehicles.json'),JSON.stringify({version:1,source:'Actual19737 CQ/G/ea/el/lifecycle + original78338/23895/66242 + originalRapier',cases}),{mode:0o600});
 console.log('PASS',cases.reduce((s,c)=>s+c.frames.length,0),'actual unattended-manager frames');
}
if(require.main===module)main().catch(error=>{console.error(error.stack);process.exitCode=1});
module.exports={managerFactory};
