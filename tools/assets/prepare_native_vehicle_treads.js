#!/usr/bin/env node
'use strict';
// Independently derive owner-local pedestrian support geometry. The result is
// original game data and must remain separate from the public source release.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {archivedModules}=require('../../tests/vehicles/smoke_vehicle_dynamics');
const {safeCatalogOutput}=require('./prepare_native_vehicle_coupling');
function main(){
 const args=process.argv.slice(2),at=args.indexOf('--output');
 if(at>=0&&!args[at+1])throw Error('--output requires a filename');
 const output=path.resolve(at>=0?args[at+1]:path.join(require('node:path').resolve(__dirname, '../..'),'local-only/selfhost/tread-catalog.json'));safeCatalogOutput(output);
 const load=archivedModules(),parse=load(78315).A,game=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game');
 const rows=JSON.parse(fs.readFileSync(path.join(game,'native/vehicles.physics.json'))).models;
 const models={},withoutMesh=[],failures=[];
 for(const row of Object.values(rows)){
  try{
   if(!Number.isInteger(row.id)||row.id<0||!/^\w+$/.test(row.model)||models[row.id])throw Error('Invalid or duplicate model identity');
   const bytes=fs.readFileSync(path.join(game,row.model+'.dff')),mesh=parse(bytes).collision?.mesh;
   if(!mesh){withoutMesh.push(row.id);continue}
   const original=mesh.positions,positions=new Float32Array(original.length),indices=Array.from(mesh.indices),movingIndices=new Set();
   if(original.length%3||indices.length%3||!Number.isFinite(row.origin))throw Error('Invalid support geometry');
   if(mesh.materials&&mesh.materials.length!==indices.length/3)throw Error('Support material count differs from topology');
   for(let i=0;i<original.length;i+=3){positions[i]=original[i];positions[i+1]=row.origin+original[i+2];positions[i+2]=-original[i+1]}
   if(!Array.from(positions).every(Number.isFinite)||!indices.every(i=>Number.isInteger(i)&&i>=0&&3*i<original.length))throw Error('Invalid support vertices/indices');
   for(let i=0;i<(mesh.materials?.length??0);i++)if(mesh.materials[i]===65)for(let j=0;j<3;j++)movingIndices.add(indices[3*i+j]);
   const moving=[...movingIndices].map(index=>({index,at:[original[3*index],row.origin+original[3*index+2],-original[3*index+1]]}));
   models[row.id]={id:row.id,model:row.model,positions:Array.from(positions),indices,moving,dffSHA256:crypto.createHash('sha256').update(bytes).digest('hex')};
  }catch(error){failures.push({id:row.id,error:error.message})}
 }
 if(failures.length)throw Error('Support conversion failed; previous catalog retained: '+JSON.stringify(failures));
 fs.mkdirSync(path.dirname(output),{recursive:true});safeCatalogOutput(output);
 const stage=fs.mkdtempSync(path.join(path.dirname(output),'.tread-stage-'));
 try{
  const sourceSHA256=crypto.createHash('sha256').update(load.factories[58683].toString()).digest('hex');
  fs.writeFileSync(path.join(stage,'catalog.json'),JSON.stringify({version:1,scope:'owner-local support query geometry; do not publish',sourceSHA256,models,withoutMesh}),{mode:0o600});
  safeCatalogOutput(output);fs.renameSync(path.join(stage,'catalog.json'),output);
 }finally{fs.rmSync(stage,{recursive:true,force:true})}
 console.log('Prepared',Object.keys(models).length,'owner-local support meshes;',withoutMesh.length,'models have no original collision mesh');
}
if(require.main===module){try{main()}catch(error){console.error(error.message);process.exitCode=1}}
