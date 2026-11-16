#!/usr/bin/env node
'use strict';
// Exercise the matched-family gate against owner-local artifacts. Fixture
// copies and corruptions are confined to a fresh ignored local directory.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {validateFamily,safeOutput}=require('./prepare_native_working_vehicles');
const {safeCatalogOutput}=require('./prepare_native_vehicle_coupling');
const root=path.join(__dirname,'local-only/native-working'),models=path.join(root,'models');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'manifest.json'),'utf8'));
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
let checks=0;
function check(value,message){checks++;assert(value,message)}
function rejects(call,message){checks++;assert.throws(call,undefined,message)}
check(manifest.models.length===6,'All configured working families must be staged');
for(const row of manifest.models){
 const meta=JSON.parse(fs.readFileSync(path.join(models,row.model+'.rig.json'),'utf8'));
 const actual=validateFamily(models,row.model,row.id,meta.cacheSignature);
 check(actual.workingParts===row.workingParts,'Manifest working hierarchy differs');
 for(const [name,expected]of Object.entries(row.files)){
  const bytes=fs.readFileSync(path.join(models,name));check(bytes.length===expected.bytes&&hash(bytes)===expected.sha256,'Manifest family hash mismatch '+name);
 }
}
const temporary=fs.mkdtempSync(path.join(root,'.stage-gate-'));
try{
 const row=manifest.models[0],prefix=path.join(temporary,row.model),metadataPath=prefix+'.rig.json';
 for(const name of Object.keys(row.files))fs.copyFileSync(path.join(models,name),path.join(temporary,name));
 const original=fs.readFileSync(metadataPath),metadata=JSON.parse(original);
 const validate=()=>validateFamily(temporary,row.model,row.id,metadata.cacheSignature);
 metadata.vertices++;fs.writeFileSync(metadataPath,JSON.stringify(metadata));rejects(validate,'Mismatched metadata and binary must fail');fs.writeFileSync(metadataPath,original);
 const normals=fs.readFileSync(prefix+'.rig.normals.bin');fs.writeFileSync(prefix+'.rig.normals.bin',normals.subarray(0,normals.length-4));rejects(validate,'Incomplete normals must fail');fs.writeFileSync(prefix+'.rig.normals.bin',normals);
 const atlas=fs.readFileSync(prefix+'.rig.png'),wrongAtlas=Buffer.from(atlas);wrongAtlas.writeUInt32BE(1,16);fs.writeFileSync(prefix+'.rig.png',wrongAtlas);rejects(validate,'Mismatched atlas dimensions must fail');fs.writeFileSync(prefix+'.rig.png',atlas);
 rejects(()=>validateFamily(temporary,row.model,row.id,'stale-generation'),'Stale metadata generation must fail');
 check(!!validate(),'Restored complete family must validate');
 rejects(()=>safeOutput(path.join(__dirname,'ios/App')),'Stage must not write public source');
 rejects(()=>safeOutput(path.join(__dirname,'local-only')),'Stage must not replace local-only root');
 const linked=path.join(temporary,'linked');fs.symlinkSync(models,linked);rejects(()=>safeOutput(path.join(linked,'child')),'Stage must reject a symlink ancestor');
 rejects(()=>safeCatalogOutput(path.join(__dirname,'ios/App/catalog.json')),'Catalog must not write public source');
 rejects(()=>safeCatalogOutput(path.join(__dirname,'local-only')),'Catalog must not replace local-only root');
 rejects(()=>safeCatalogOutput(path.join(linked,'catalog.json')),'Catalog must reject a symlink ancestor');
 rejects(()=>safeCatalogOutput(temporary),'Catalog must not replace an existing directory');
 const catalogLink=path.join(temporary,'catalog-link.json');fs.symlinkSync(path.join(root,'manifest.json'),catalogLink);rejects(()=>safeCatalogOutput(catalogLink),'Catalog must reject a leaf link');
 const dangling=path.join(temporary,'dangling');fs.symlinkSync(path.join(temporary,'absent'),dangling);
 rejects(()=>safeOutput(dangling),'Stage must reject a dangling leaf link');rejects(()=>safeOutput(path.join(dangling,'models')),'Stage must reject a dangling ancestor');
 rejects(()=>safeCatalogOutput(dangling),'Catalog must reject a dangling leaf link');rejects(()=>safeCatalogOutput(path.join(dangling,'catalog.json')),'Catalog must reject a dangling ancestor');
 safeCatalogOutput(path.join(temporary,'safe','catalog.json'));checks++;
 safeOutput(path.join(temporary,'safe','models'));checks++;
}finally{fs.rmSync(temporary,{recursive:true,force:true})}
console.log('PASS complete working rig stage:',checks,'checks; six matched four-file families, stale/mixed/incomplete data and shared/public outputs rejected');
