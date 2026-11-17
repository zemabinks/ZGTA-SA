#!/usr/bin/env node
'use strict';
// Exercise the matched-family gate against owner-local artifacts. Fixture
// copies and corruptions are confined to a fresh ignored local directory.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {validateFamily,safeOutput}=require('./prepare_native_working_vehicles');
const {safeCatalogOutput}=require('./prepare_native_vehicle_coupling');
const args=process.argv.slice(2),option=name=>{const at=args.indexOf(name);if(at<0)return null;if(!args[at+1])throw Error(name+' requires a directory');return path.resolve(args[at+1])};
const root=option('--root')??path.join(__dirname,'local-only/native-working'),models=path.join(root,'models');
const legacyRoot=option('--legacy-root');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'manifest.json'),'utf8'));
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
let checks=0;
function check(value,message){checks++;assert(value,message)}
function rejects(call,message,pattern){checks++;assert.throws(call,pattern,message)}
check(manifest.models.length===6,'All configured working families must be staged');
for(const row of manifest.models){
 const meta=JSON.parse(fs.readFileSync(path.join(models,row.model+'.rig.json'),'utf8'));
 const actual=validateFamily(models,row.model,row.id,meta.cacheSignature);
 check(actual.workingParts===row.workingParts,'Manifest working hierarchy differs');
 for(const [name,expected]of Object.entries(row.files)){
  const bytes=fs.readFileSync(path.join(models,name));check(bytes.length===expected.bytes&&hash(bytes)===expected.sha256,'Manifest family hash mismatch '+name);
 }
}
// Read the adopted stage without creating scratch files beneath it. This also
// lets migration tests target a newly prepared, isolated --root directory.
const scratch=path.join(__dirname,'local-only/research/working-stage-gate');fs.mkdirSync(scratch,{recursive:true});
const temporary=fs.mkdtempSync(path.join(scratch,'fixture-'));
try{
 const row=manifest.models[0],prefix=path.join(temporary,row.model),metadataPath=prefix+'.rig.json';
 for(const name of Object.keys(row.files))fs.copyFileSync(path.join(models,name),path.join(temporary,name));
 const original=fs.readFileSync(metadataPath),metadata=JSON.parse(original);
 const validate=()=>validateFamily(temporary,row.model,row.id,metadata.cacheSignature);
 metadata.vertices++;fs.writeFileSync(metadataPath,JSON.stringify(metadata));rejects(validate,'Mismatched metadata and binary must fail');fs.writeFileSync(metadataPath,original);
 const normals=fs.readFileSync(prefix+'.rig.normals.bin');fs.writeFileSync(prefix+'.rig.normals.bin',normals.subarray(0,normals.length-4));rejects(validate,'Incomplete normals must fail');fs.writeFileSync(prefix+'.rig.normals.bin',normals);
 const atlas=fs.readFileSync(prefix+'.rig.png'),wrongAtlas=Buffer.from(atlas);wrongAtlas.writeUInt32BE(1,16);fs.writeFileSync(prefix+'.rig.png',wrongAtlas);rejects(validate,'Mismatched atlas dimensions must fail');fs.writeFileSync(prefix+'.rig.png',atlas);
 rejects(()=>validateFamily(temporary,row.model,row.id,'stale-generation'),'Stale metadata generation must fail');
 rejects(()=>validateFamily(temporary,row.model,row.id,'0'.repeat(64)),'Well-formed stale generation must fail',/identity/);
 rejects(()=>validateFamily(temporary,row.model,row.id+1,metadata.cacheSignature),'Wrong expected model ID must fail',/identity/);
 const originalMetadata=JSON.parse(original),binary=fs.readFileSync(prefix+'.rig.bin');
 function badMetadata(change,message,pattern){
  const value=JSON.parse(original);change(value);fs.writeFileSync(metadataPath,JSON.stringify(value));
  try{rejects(validate,message,pattern)}finally{fs.writeFileSync(metadataPath,original)}
 }
 function badComponent(suffix,change,message,pattern,rehash=false){
  const file=prefix+suffix,before=fs.readFileSync(file),value=Buffer.from(before),document=JSON.parse(original);change(value);
  fs.writeFileSync(file,value);
  if(rehash){const field={'.rig.bin':'binarySHA256','.rig.png':'atlasSHA256','.rig.normals.bin':'normalsSHA256'}[suffix];document[field]=hash(value);fs.writeFileSync(metadataPath,JSON.stringify(document))}
  try{rejects(validate,message,pattern)}finally{fs.writeFileSync(file,before);fs.writeFileSync(metadataPath,original)}
 }
 badMetadata(m=>m.version=3,'Unknown schema must fail',/identity/);
 badMetadata(m=>m.id++,'Relabelled model must fail',/identity/);
 badMetadata(m=>m.vertices=1000000,'Excessive vertex count must fail',/buffer counts/);
 badMetadata(m=>m.indices=3.5,'Fractional index count must fail',/buffer counts/);
 badMetadata(m=>m.nodes[0].parent=0,'Parent cycle must fail',/hierarchy/);
 badMetadata(m=>m.draws[0].node=0.5,'Fractional node must fail',/hierarchy/);
 badMetadata(m=>m.draws[0].start=0.5,'Fractional draw range must fail',/hierarchy/);
 badMetadata(m=>m.draws[0].count=m.indices+3,'Out-of-buffer draw must fail',/hierarchy/);
 badMetadata(m=>m.draws[0].texture=m.textures.length+1,'Out-of-atlas draw must fail',/hierarchy/);
 badMetadata(m=>m.nodes[0].matrix[0]=null,'Nonfinite node matrix must fail',/hierarchy/);
 badMetadata(m=>m.joints.working.parts[0]&&(m.joints.working.parts[0].node=m.nodes.length),'Invalid working node must fail',/working/);
 if(originalMetadata.version===2){
  check(binary.subarray(0,4).toString()==='VPC2','Neutral stage requires VPC2');
  for(const suffix of ['.rig.bin','.rig.png','.rig.normals.bin'])badComponent(suffix,b=>b[b.length-1]^=1,'Tampered v2 component must fail its hash',/hash mismatch/);
  badMetadata(m=>m.version=1,'Relabelled v2 must not bypass hashes/encoding',/Legacy rig/);
  badMetadata(m=>m.binaryEncoding='WRL2','Mixed v2 declaration must fail',/encoding/);
  badMetadata(m=>delete m.atlasSHA256,'Missing atlas hash must fail',/hash mismatch/);
  badMetadata(m=>m.normalsSHA256='0'.repeat(64),'Mismatched normals hash must fail',/hash mismatch/);
  badMetadata(m=>m.paint.palette[0][0]=256,'Invalid palette must fail',/paint metadata/);
  badMetadata(m=>m.paint.colorVariants=[[0,1]],'Invalid variant must fail',/paint metadata/);
  badMetadata(m=>m.draws[0].paint=4,'Unsupported material slot must fail',/hierarchy/);
  badComponent('.rig.bin',b=>b.writeUInt32LE(0x324c5257,0),'Old baked binary with updated hash must fail',/binary\/metadata/,true);
  badComponent('.rig.bin',b=>b.writeFloatLE(NaN,16),'Nonfinite position with updated hash must fail',/Nonfinite/,true);
  badComponent('.rig.bin',b=>b.writeUInt32LE(originalMetadata.vertices,16+originalMetadata.vertices*20),'Out-of-range vertex with updated hash must fail',/vertex index/,true);
  badComponent('.rig.bin',b=>b.writeUInt16LE(originalMetadata.textures.length+1,16+originalMetadata.vertices*20+originalMetadata.indices*4+originalMetadata.vertices*4),'Out-of-range layer with updated hash must fail',/texture layer/,true);
  badComponent('.rig.normals.bin',b=>b.writeFloatLE(Infinity,0),'Nonfinite normal with updated hash must fail',/Nonfinite/,true);
  badComponent('.rig.png',b=>b.writeUInt32BE(1,16),'Wrong atlas size with updated hash must fail',/atlas mismatch/,true);
  // An independently constructed legacy-format contract is still accepted.
  // It is a format compatibility test, not a claim of legacy visual parity.
  const legacy=JSON.parse(original),legacyBytes=Buffer.from(binary);legacy.version=1;legacyBytes.writeUInt32LE(0x324c5257,0);
  for(const field of ['paint','binaryEncoding','binarySHA256','atlasSHA256','normalsSHA256'])delete legacy[field];
  fs.writeFileSync(metadataPath,JSON.stringify(legacy));fs.writeFileSync(prefix+'.rig.bin',legacyBytes);
  check(!!validate(),'Explicit legacy WRL2 contract must remain accepted');
  fs.writeFileSync(prefix+'.rig.bin',binary);rejects(validate,'Neutral binary must not upload as legacy',/binary\/metadata/);
  fs.writeFileSync(metadataPath,original);
 }else{check(binary.subarray(0,4).toString()==='WRL2','Legacy stage requires WRL2')}
 if(legacyRoot)for(const entry of manifest.models){
  const doc=JSON.parse(fs.readFileSync(path.join(legacyRoot,entry.model+'.rig.json'),'utf8'));
  check(doc.version===1,'Explicit original legacy reference must be v1');
  check(!!validateFamily(legacyRoot,entry.model,entry.id,doc.cacheSignature),'Original complete v1 family must remain accepted');
 }
 check(!!validate(),'Restored complete family must validate');
 rejects(()=>safeOutput(path.join(__dirname,'ios/App')),'Stage must not write public source');
 rejects(()=>safeOutput(path.join(__dirname,'local-only')),'Stage must not replace local-only root');
 rejects(()=>safeOutput(__dirname),'Stage must not replace the project root');
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
