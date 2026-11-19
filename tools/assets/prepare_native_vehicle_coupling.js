#!/usr/bin/env node
'use strict';
// Derive owner-local hitch/working-part facts from the archived client. This
// independent importer never publishes original scripts or generated catalogs.
const fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const {archivedModules}=require('../../tests/vehicles/smoke_vehicle_dynamics');
const hash=value=>createHash('sha256').update(value).digest('hex');

function reference(load=archivedModules()) {
  const source=load.factories[19737].toString(),T=load(85339);
  function between(start,end){const a=source.indexOf(start),b=source.indexOf(end,a);if(a<0||b<=a)throw Error('Archived coupling signature changed: '+start);return source.slice(a,b)}
  const trailer=between('let ml=[0,11,17,18],mn=[12,18],mr=','var mf=l(91584)');
  const working=between('let vn={','let va=');
  const parts=between('function x9(e,t){','function x7(');
  const turn=between('let ve=new d.PTz;function vt(','var vl=');
  const posing=between('let va=[["misc_a",null]','vi=new d.Pq0').replace(/,$/,';');
  const axes=between('x8={X:new d.Pq0(1,0,0)',';function x9(');
  const helpers=Function('d',trailer+working+parts+turn+';let '+axes+';'+posing+
    ';return {rear:mc,hook:mu,front:vr,targets:mo,working:vn,prepare:(e)=>{let t=vn[Number(e.id)];if(t)vo(e,t,0)},pose:(e,t)=>{let l=vn[Number(e.id)];if(l)vo(e,l,t)}};')(T);
  const vector=v=>v?[v.x,v.y,v.z]:null;
  function configuration(built){
    const id=Number(built.id),definition=built.definition??{},kind=built.kind??load(72197).I(definition)??'car';
    const row={...built,id,kind,origin:built.origin??built.root.position.y};
    const work=helpers.working[id],available=work ? (work.tow ? row.root.userData.frames.has('misc_a'):row.root.userData.frames.has(work.frame)):false;
    const frame=work?.frame?row.root.userData.frames.get(work.frame):null,at=frame?new T.Pq0().setFromMatrixPosition(frame):null;
    const pivot=at?[at.x,row.origin+at.z,-at.y]:null;
    return {id,kind,origin:row.origin,minimum:[...row.bounds.box.min],maximum:[...row.bounds.box.max],
      rearAnchor:vector(helpers.rear(row)),trailerAnchor:vector(helpers.hook(row)),frontAnchor:vector(helpers.front(row)),
      targets:[...(helpers.targets.get(id)??[])],working:work?{...work,available,pivot,movingShapes:built.movingShapes??[]}:null};
  }
  return {load,T,configuration,prepare:helpers.prepare,pose:helpers.pose,
    sourceSHA256:hash(source),helperSHA256:hash(trailer+working+parts+turn+posing+axes)};
}

async function buildCatalogue(options={}) {
  const load=options.load??archivedModules(),ref=reference(load),T=ref.T,catalogue=load(72197),geometry=load(88711),handling=load(87605);
  const game=options.game??path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game'),models={},failures=[];let R;
  for(const definition of catalogue.Wd){
    const id=Number(definition.id);let root;
    try{
      const bytes=fs.readFileSync(path.join(game,definition.model+'.dff')),parsed=load(78315).A(bytes),assets=catalogue.yc(catalogue.AX({id}));
      root=geometry.yK(parsed,new Map(),{kind:'vehicle',damage:true,blades:true,lowDetail:true,wheels:load(90317).y(id)});
      geometry.u2(root,[],new Map(),{colors:assets.colors,wheelScale:assets.wheelScale});
      const wheels=load(74921).p(root,assets.stance),box=new T.NRn().setFromObject(root),size=box.getSize(new T.Pq0());
      root.position.y=-box.min.y;const body=new T.YJl();body.add(root);handling.FV(id,body,root,wheels);
      const built={id,definition,root,origin:root.position.y,length:size.z,bounds:handling.BO(parsed.collision,size,root.position.y)};
      const profile=ref.configuration(built);
      if(profile.working?.available&&!profile.working.tow){
        if(!R){R=load(55077);await R.init()}
        const world=new R.World({x:0,y:0,z:0});
        try{
          const rigid=world.createRigidBody(R.RigidBodyDesc.dynamic()),table=handling.c_(id,size).table;
          const source={...built,id:String(id),kind:profile.kind,table,collision:parsed.collision};
          const solids=load(23895).vX({RAPIER:R,world},source,rigid,327663);
          built.movingShapes=solids.moving.map(({collider,at})=>({index:solids.indexOf(collider),at:[at.x,at.y,at.z]}));
        }finally{world.free()}
      }
      models[id]={...ref.configuration(built),dffSHA256:hash(bytes)};
    }catch(error){failures.push({id,error:error.message})}finally{if(root)geometry.xd(root,null)}
  }
  return {version:1,axes:'Rapier Y-up [GTA x,GTA z,-GTA y]',sourceSHA256:ref.sourceSHA256,helperSHA256:ref.helperSHA256,models,failures};
}

function safeCatalogOutput(output){
  const local=path.resolve(require('node:path').resolve(__dirname, '../..'),'local-only'),relative=path.relative(local,output);
  if(relative===''||relative.startsWith('..'+path.sep)||path.isAbsolute(relative))throw Error('Coupling catalog must stay under this project local-only directory');
  function status(file){try{return fs.lstatSync(file)}catch(error){if(error.code==='ENOENT')return null;throw error}}
  let current=local;
  for(const part of relative.split(path.sep)){
    const info=status(current);if(info?.isSymbolicLink())throw Error('Refusing shared catalog output ancestor '+current);
    current=path.join(current,part);
  }
  const info=status(current);
  if(info?.isSymbolicLink())throw Error('Refusing shared catalog output link');
  if(info&&!info.isFile())throw Error('Catalog output must be a file');
}

async function main(){
  const args=process.argv.slice(2),at=args.indexOf('--output');
  const output=path.resolve(at>=0?args[at+1]:path.join(require('node:path').resolve(__dirname, '../..'),'local-only/selfhost/coupling-catalog.json'));
  if(at>=0&&!args[at+1])throw Error('--output requires a filename');
  safeCatalogOutput(output);fs.mkdirSync(path.dirname(output),{recursive:true});safeCatalogOutput(output);
  const result=await buildCatalogue();
  if(result.failures.length){for(const row of result.failures)console.error(row.id,row.error);throw Error('Incomplete coupling catalog; previous local catalog preserved')}
  const stage=fs.mkdtempSync(path.join(path.dirname(output),'.coupling-stage-'));
  try{
    const temporary=path.join(stage,'catalog.json');fs.writeFileSync(temporary,JSON.stringify(result),{mode:0o600});
    safeCatalogOutput(output);fs.renameSync(temporary,output);
  }finally{fs.rmSync(stage,{recursive:true,force:true})}
  const rows=Object.values(result.models);console.log('Prepared',rows.length,'local coupling profiles,',rows.filter(x=>x.rearAnchor).length,'rear hitches,',rows.filter(x=>x.trailerAnchor).length,'trailer hooks,',rows.filter(x=>x.working).length,'working vehicles,',result.failures.length,'failures');
}
if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1});
module.exports={reference,buildCatalogue,safeCatalogOutput};
