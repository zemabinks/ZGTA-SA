#!/usr/bin/env node
// Actual archived62540 contact closure +66242 damage, running original WASM.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),{archivedModules}=require('../../smoke_vehicle_dynamics');
async function main(){
 const load=archivedModules(),R=load(55077);await R.init();const T=load(85339),D=load(66242),source=fs.readFileSync(path.join(__dirname,'../../local-only/reverse-engineering/vehicle-physics/module-62540.js'),'utf8');
 const start=source.indexOf('let { world: e, events: t } = o,'),end=source.indexOf('})(),\n          tc(e)',start);if(start<0||end<0)throw Error('Archived contact closure changed');
 const vector=v=>[v.x,v.y,v.z],cases=[];
 for(const [name,piece,material,otherVehicle,rhino,flight,sphere,floor] of [['front',3,0,false,false,false,false,false],['bonnet',1,0,false,false,false,true,false],['door',5,0,false,false,false,false,false],['wing',9,0,false,false,false,false,false],['glass',19,0,false,false,false,false,false],['vehicle',4,63,true,false,false,false,false],['rhino',3,63,true,true,false,false,false],['pedestrian',3,62,false,false,false,false,false],['floor-protection',3,0,false,false,false,false,true],['flight-floor',3,0,false,false,true,false,true]]){
  const world=new R.World({x:0,y:floor?-9.81:0,z:0}),queue=new R.EventQueue(true),mass=1400,origin=1.2;
  const other=world.createCollider(floor?R.ColliderDesc.cuboid(30,.1,30):R.ColliderDesc.cuboid(30,30,.5).setTranslation(0,0,-10));
  const body=world.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(0,floor?8:0,0).setCcdEnabled(true).setCanSleep(false).setAdditionalMassProperties(mass,{x:0,y:0,z:0},{x:3500,y:3500,z:3500},{x:0,y:0,z:0,w:1}));
  body.setLinvel({x:0,y:floor?-5:0,z:floor?0:-30},true);
  const desc=(sphere?R.ColliderDesc.ball(.8):R.ColliderDesc.cuboid(1,.6,2)).setDensity(0).setFriction(.5).setFrictionCombineRule(R.CoefficientCombineRule.Min).setActiveEvents(R.ActiveEvents.CONTACT_FORCE_EVENTS),chassis=world.createCollider(desc,body),damage=D._E({mass,collisionDamage:.65},{maxX:1},0,420);
  const hinges=Array.from({length:6},(_,j)=>new T.Pq0(j%2?1:-1,.3,-1+j*.5));damage.letGo(0,.6);damage.letGo(2,-.8);
  const bodyFrame=()=>{const p=body.translation(),r=body.rotation(),q=new T.PTz(r.x,r.y,r.z,r.w),up=new T.Pq0(0,1,0).applyQuaternion(q);return{position:new T.Pq0(p.x,p.y,p.z).addScaledVector(up,origin),right:new T.Pq0(1,0,0).applyQuaternion(q),forward:new T.Pq0(0,0,-1).applyQuaternion(q),up,move:new T.Pq0(...vector(body.linvel())).divideScalar(50),turn:new T.Pq0(...vector(body.angvel())).divideScalar(50)}};
  const context=vm.createContext({o:{world,events:queue,materials:new Map([[other.handle,material]]),others:new Set(otherVehicle?[other.handle]:[]),rhinos:new Set(rhino?[other.handle]:[])},c:{solids:{pieces:new Map([[chassis.handle,piece]])},flight,rigid:body},n:T,Z:D,J:load(77287),eI:damage,to:new Map(),ta:{touch(){},sparks(){}},e6:bodyFrame,e4:new T.Pq0,eZ:1/60,eU:null,ti:false,ts:0,s:null,i:null,d:{pedalled:false,table:{mass}},ey:true,td(){},performance:{now:()=>0}});
  const settle=vm.runInContext('(function(){'+source.slice(start,end)+'})',context),frames=[];
  for(let i=0;i<240;i++){
   const before=bodyFrame();context.eU=before;world.step(queue);settle();const now=bodyFrame(),impact=damage.intensity;damage.process(now,50/60);damage.swing(now,before,now,j=>hinges[j].clone().applyQuaternion(body.rotation()),50/60,impact);
   if(damage.events.some(e=>e.type==='blow'))damage.blowUp();
   frames.push({position:vector(body.translation()),velocity:vector(body.linvel()),health:damage.health,text:damage.toText(),doors:Array.from({length:6},(_,j)=>damage.door(j).angle),events:damage.events.map(e=>({type:e.type,part:e.part??null,force:e.force??null,point:e.point?vector(e.point):null}))});damage.events.length=0;
  }
  cases.push({name,piece,material,otherVehicle,rhino,flight,sphere,floor,mass,origin,hinges:hinges.map(vector),frames});queue.free();world.free();
 }
 const output=path.join(__dirname,'../../local-only/physics-fixtures/damage-integration.json');fs.writeFileSync(output,JSON.stringify({version:1,cases}),{mode:0o600});console.log('PASS captured actual62540/66242+WASM damage contact references:',cases.length*240,'frames');
}
main().catch(e=>{console.error(e);process.exitCode=1});
