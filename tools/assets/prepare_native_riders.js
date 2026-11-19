#!/usr/bin/env node
// Execute the public client's actual bv/bk seat builder on archived DFFs.
// Complete seat/door/boarding data remains local, alongside game assets.
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {archivedModules} = require('../../tests/vehicles/smoke_vehicle_dynamics');

function main() {
  const load = archivedModules(), T = load(85339), factory = load.factories[49368];
  const chunks = path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/_next/static/chunks');
  const filename = fs.readdirSync(chunks).find(name=>name.endsWith('.js')&&fs.readFileSync(path.join(chunks,name),'utf8').includes('function bv(e){var t,l;let n=e.root.userData.frames'));
  if (!filename) throw Error('Original public seat builder unavailable');
  const source = fs.readFileSync(path.join(chunks,filename),'utf8');
  const table = source.match(/\by5=JSON\.parse\('((?:\\.|[^'\\])*)'\)/);
  if (!table) throw Error('Original rider groups unavailable');
  const groups = JSON.parse(factory.constructor("return '"+table[1]+"'")());
  const declaration = (begin,end) => {const at=source.indexOf(begin),last=source.indexOf(end,at);if(at<0||last<0)throw Error('Original seat clause unavailable:'+begin);return source.slice(at,last)};
  const at = source.lastIndexOf('bn=',source.indexOf('function bv('));
  const constants = source.slice(at,source.indexOf(',bi=',at));
  const module = source.match(/\by4=l\((\d+)\)/);
  if (!module) throw Error('Original vehicle-door module unavailable');
  const code = `let ${constants};const by=e=>e.kind==='boat';let bx={opens:false,door:null};${declaration('function bm(','let bf=')}${declaration('function bb(','let bx=')}${declaration('function bv(','let bj=')}return {seats:bv,profile:bm}`;
  const original = factory.constructor('d','y4','y5',code)(T,load(Number(module[1])),groups);
  const game = path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game');
  const physics = JSON.parse(fs.readFileSync(path.join(game,'native/vehicles.physics.json'))).models;
  const seating = JSON.parse(fs.readFileSync(path.join(game,'native/seating.json'))).models;
  const geometry = load(88711), catalogue = load(72197), parse = load(78315).A, models = {}, withoutSeat = [];
  for (const definition of catalogue.Wd) {
    const id = String(definition.id), configuration = physics[id];
    if (!configuration || !seating[id]) continue;
    const bytes = fs.readFileSync(path.join(game,definition.model+'.dff'));
    const root = geometry.yK(parse(bytes),new Map(),{kind:'vehicle',damage:true,blades:true,lowDetail:true,wheels:load(90317).y(Number(id))});
    const built = {id:Number(id),root,kind:configuration.kind,table:configuration.table};
    const seats = original.seats(built).map(value=>({...value,at:value.at.toArray(),
      ...value.via?{via:value.via.toArray()}:{},...value.shift?{shift:value.shift.toArray()}:{} }));
    if (!seats.length) withoutSeat.push(id);
    models[id] = {model:definition.model,astride:!!original.profile(Number(id)).astride,astrideKind:original.profile(Number(id)).astride,afloat:configuration.kind==='boat',clips:seating[id].clips,
      driverSeat:seats[0]?.at ?? null,driverSide:seats[0]?.side ?? 0,seats,origin:configuration.origin,bike:configuration.bike ?? null,group:original.profile(Number(id)).group,
      sha256:createHash('sha256').update(bytes).digest('hex')};
    root.traverse(object=>{if(object.isMesh){object.geometry.dispose();for(const material of [object.material].flat())material?.dispose()}});
  }
  const output = path.join(game,'native/riders.json');
  fs.writeFileSync(output,JSON.stringify({version:2,models,withoutSeat,source:{[filename]:createHash('sha256').update(source).digest('hex')}})+'\n',{mode:0o600});
  const seats = Object.values(models).reduce((sum,model)=>sum+model.seats.length,0);
  console.log(`Prepared ${seats} exact original rider seats for ${Object.keys(models).length} models; ${withoutSeat.length} original models have no seat`);
}
if (require.main === module) {try {main()} catch(error) {console.error(error.stack);process.exitCode=1}}
module.exports = {main};
