#!/usr/bin/env node
// Run the archived public car solver in an isolated, offline VM to produce
// reference measurements for the independent Swift translation. Raw bundles,
// WASM and handling values stay under ignored local-only/.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {webcrypto} = require('node:crypto');

function archivedModules() {
  const directory = path.join(__dirname, 'local-only/site/_next/static/chunks');
  const fixtureMath = Object.create(Math); fixtureMath.random = () => 0.37;
  const context = vm.createContext({crypto: webcrypto, TextDecoder,
    TextEncoder, WebAssembly, Math: fixtureMath, performance: {now: () => 0},
    console: {warn() {}, error(...values) {console.error('Archived physics:', ...values);}},
    fetch: () => {throw new Error('Physics fixtures cannot access the network');}});
  vm.runInContext('self = globalThis; self.webpackChunk_N_E = [];', context);
  for (const name of fs.readdirSync(directory)) {
    if (!name.endsWith('.js') || name.startsWith('webpack-')) continue;
    const source = fs.readFileSync(path.join(directory, name), 'utf8');
    if (!source.includes('webpackChunk_N_E') || !source.includes('.push([[')) continue;
    vm.runInContext(source, context, {timeout: 5000, filename: name});
  }
  const factories = Object.assign({}, ...context.self.webpackChunk_N_E.map(row => row[1]));
  const cache = new Map();
  const load = id => {
    if (cache.has(id)) return cache.get(id).exports;
    if (!factories[id]) throw new Error('Archived module is unavailable: ' + id);
    const module = {exports: {}};
    cache.set(id, module);
    factories[id](module, module.exports, load);
    return module.exports;
  };
  load.d = (target, values) => {for (const [name, get] of Object.entries(values))
    Object.defineProperty(target, name, {enumerable: true, get});};
  load.r = target => Object.defineProperty(target, '__esModule', {value: true});
  load.o = (object, name) => Object.prototype.hasOwnProperty.call(object, name);
  load.n = object => {const getter = object?.__esModule ? () => object.default : () => object;
    load.d(getter, {a: getter}); return getter;};
  load.e = () => Promise.reject(new Error('Fixture dynamic imports are disabled'));
  load.factories = factories;
  return load;
}

async function main() {
  const load = archivedModules();
  const R = load(55077);
  await R.init();
  const THREE = load(85339), solver = load(23895);
  console.log('Original Rapier JS binding', R.version(), 'Three Vector3', typeof THREE.Pq0);
  assert.equal(R.version(), '0.20.0');
  assert.equal(typeof solver.Xn, 'function');
  if (process.argv.includes('--generate')) {
    const table = load(87605).c_(420, new THREE.Pq0(2, 1.8, 5)).table;
    const wheelSpecs = [[true,true],[false,true],[true,false],[false,false]].map(([front,left]) =>
      ({centre: [left ? -0.92 : 0.92,-0.35,front ? -1.63719 : 1.64388],
        radius: 0.35,front,left}));
    const config = {model:420,origin:0,kind:'car',table,wheels:wheelSpecs};
    const cases = [];
    const scenarios = [
      {name:'straight',steps:420,height:0.8,input:i=>({throttle:i<60?0:1,steer:0})},
      {name:'brake',steps:600,height:0.8,input:i=>({throttle:i<60?0:i<360?1:-1,steer:0})},
      {name:'turn',steps:600,height:0.8,input:i=>({throttle:i<60?0:1,steer:i<240?0:0.6})},
      {name:'suspension',steps:240,height:2.5,input:()=>({throttle:0,steer:0})},
      {name:'reverse',steps:420,height:0.8,input:i=>({throttle:i<60?0:-1,steer:i<240?0:0.35})},
      {name:'handbrake',steps:480,height:0.8,input:i=>({throttle:i<60?0:1,steer:i<240?0:0.6,handbrake:i>=240&&i<360})},
      {name:'rear-steer',steps:480,height:0.8,table:{flags:64,drive:'R'},input:i=>({throttle:i<60?0:1,steer:i<180?0:0.5,handbrake:i>=240&&i<360})},
      {name:'abs',steps:600,height:0.8,table:{abs:true},input:i=>({throttle:i<60?0:i<360?1:-1,steer:i<360?0:0.4})},
      {name:'wet-turn',steps:600,height:0.8,input:i=>({throttle:i<60?0:1,steer:i<240?0:0.6,wetness:0.8})},
      {name:'nitro',steps:480,height:0.8,nitro:true,actions:i=>i===90?{fire:true}:null,input:i=>({throttle:i<60?0:1,steer:0})},
      {name:'air-control',steps:240,height:20,input:i=>({throttle:0,steer:0.7,lean:0.6,pad:true,handbrake:i>=120})},
      {name:'hydraulics',steps:480,height:0.8,hydraulics:true,table:{flags:65536},
        input:i=>({throttle:i<180?0:1,steer:0,suspensionOffsets:i<180?[Math.sin(i/20)*0.07,0,Math.sin(i/20)*0.07,0]:[]})},
      {name:'manual',steps:600,height:0.8,manual:true,actions:i=>[180,300,420].includes(i)?{shift:1}:i===500?{shift:-1}:null,
        input:i=>({throttle:i<60?0:1,steer:0})},
      {name:'burnout',steps:480,height:0.8,table:{drive:'R'},
        input:i=>({throttle:i<60?0:1,steer:0.5,accelerate:i<60?0:1,brake:i>=60&&i<180?1:0})},
      {name:'fun-boost',steps:480,height:0.8,fun:2,input:i=>({throttle:i<60?0:1,steer:0})},
      {name:'burst-tyre',steps:480,height:0.8,tyres:[1,0,0,0],input:i=>({throttle:i<60?0:1,steer:0})},
      {name:'missing-tyre',steps:480,height:0.8,tyres:[2,0,0,0],input:i=>({throttle:i<60?0:1,steer:0})},
    ];
    for (const scenario of scenarios) {
      const world = new R.World({x:0,y:-9.81,z:0});
      world.createCollider(R.ColliderDesc.cuboid(1000,0.1,1000).setTranslation(0,-0.1,0));
      const settings={table:{...table,...scenario.table},nitro:!!scenario.nitro,hydraulics:!!scenario.hydraulics,
        manual:!!scenario.manual,fun:scenario.fun??0,tyres:scenario.tyres??[]};
      const built = {...config,...settings,id:'420',nitro:scenario.nitro?5:0,width:2,height:1.8,length:5,
        bounds:{box:{min:[-1,-2.5,-0.5],max:[1,2.5,0.7]}},
        collision:{spheres:[],boxes:[{min:[-1,-2.5,-0.5],max:[1,2.5,0.7],piece:0,material:0}]},
        wheels:wheelSpecs.map(w=>({...w,centre:new THREE.Pq0(...w.centre)}))};
      let queries=[];
      const cast = world.castRayAndGetNormal.bind(world);
      world.castRayAndGetNormal = (...args) => {
        const hit=cast(...args);
        queries.push(hit?{distance:hit.timeOfImpact,normal:[hit.normal.x,hit.normal.y,hit.normal.z],surface:2,material:-1}:null);
        return hit;
      };
      const car = solver.Xn({RAPIER:R,world,waterLevel:()=>null},built,420);
      car.manual=settings.manual;car.fun=settings.fun;car.setTyres(settings.tyres);
      car.rigid.setTranslation({x:0,y:scenario.height,z:0},true);
      let requestedLinear,requestedAngular;
      const setLinear=car.rigid.setLinvel.bind(car.rigid),setAngular=car.rigid.setAngvel.bind(car.rigid);
      car.rigid.setLinvel=(value,wake)=>{requestedLinear=[value.x,value.y,value.z];setLinear(value,wake)};
      car.rigid.setAngvel=(value,wake)=>{requestedAngular=[value.x,value.y,value.z];setAngular(value,wake)};
      world.step();
      const frames=[];
      for(let i=0;i<scenario.steps;i++) {
        const p=car.rigid.translation(),q=car.rigid.rotation(),v=car.rigid.linvel(),a=car.rigid.angvel();
        const body={position:[p.x,p.y,p.z],rotation:[q.x,q.y,q.z,q.w],linearVelocity:[v.x,v.y,v.z],angularVelocity:[a.x,a.y,a.z]};
        queries=[];const input=scenario.input(i),actions=scenario.actions?.(i)??null;
        load(74348).Ig.value=input.wetness??0;
        if(actions?.fire)car.fire();if(actions?.shift)car.shift(actions.shift);
        car.step(1/60,input,input.suspensionOffsets?.length?input.suspensionOffsets:null);
        frames.push({body,input,actions,rays:queries,linearVelocity:requestedLinear,angularVelocity:requestedAngular,
          steering:car.steer,rearSteering:car.rearSteer,gear:car.gear,gas:car.gas,burnout:car.burnout,
          wheels:car.lines.map(w=>({index:w.index,compression:w.compression,offset:w.offset,counts:w.counts,
            state:w.state,spin:w.spin*50,point:[w.point.x,w.point.y,w.point.z],normal:[w.normal.x,w.normal.y,w.normal.z]}))});
        world.step();
      }
      const final=car.rigid.translation();
      cases.push({name:scenario.name,settings,frames,final:[final.x,final.y,final.z]});
      world.free();
      console.log(scenario.name,'frames',frames.length,'final',cases.at(-1).final);
    }
    const destination=path.join(__dirname,'local-only/physics-fixtures');fs.mkdirSync(destination,{recursive:true});
    fs.writeFileSync(path.join(destination,'vehicle-dynamics.json'),JSON.stringify({version:1,
      source:'archived 3895 module23895 with original embedded Rapier',
      chassis:'Synthetic calibration box and explicitly specified wheel hubs; handling uses archived Taxi420 row',
      delta:1/60,config,cases}),{mode:0o600});
    console.log('PASS: original grounded-car reference traces saved locally');
  }
  console.log('PASS: archived vehicle solver loads offline with its original Rapier and Three runtime');
}
if (require.main === module) main().catch(error => {console.error(error); process.exitCode = 1;});
module.exports = {archivedModules};
