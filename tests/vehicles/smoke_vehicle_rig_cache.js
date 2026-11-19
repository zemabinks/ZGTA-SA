#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const {createLibrary,exportRig}=require('../../tools/assets/prepare_native_vehicle_rigs');
function main(){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'zgtasa-rig-cache-')),game=path.join(root,'game'),output=path.join(game,'native/models');
  fs.mkdirSync(game,{recursive:true});
  for(const name of ['bmx.dff','bmx.txd','vehicle.txd'])fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game',name),path.join(game,name));
  let library=createLibrary({game}),definition=library.catalogue.Wd.find(row=>Number(row.id)===481);
  const metadata=exportRig(library.build(481),output);
  assert(library.cached(definition,output));assert.equal(metadata.cacheSignature,library.signature(definition).sha256);
  assert(metadata.cacheSourceSHA256.length===64);assert.equal(metadata.cacheInputs.length,3);
  for(const suffix of ['.bin','.png','.json','.normals.bin']){
    const file=path.join(output,'bmx.rig'+suffix),saved=fs.readFileSync(file);fs.unlinkSync(file);
    assert(!createLibrary({game}).cached(definition,output),'Missing output must rebuild: '+suffix);
    fs.writeFileSync(file,saved);
  }
  for(const name of ['bmx.dff','bmx.txd','vehicle.txd']){
    const file=path.join(game,name),saved=fs.readFileSync(file),changed=Buffer.from(saved);changed[changed.length-1]^=1;fs.writeFileSync(file,changed);
    assert(!createLibrary({game}).cached(definition,output),'Changed input must rebuild: '+name);
    fs.writeFileSync(file,saved);
  }
  const file=path.join(output,'bmx.rig.json'),saved=fs.readFileSync(file),changed=JSON.parse(saved);changed.cacheSignature='stale';fs.writeFileSync(file,JSON.stringify(changed));
  assert(!createLibrary({game}).cached(definition,output));fs.writeFileSync(file,saved);
  assert(createLibrary({game}).cached(definition,output));
  console.log('PASS complete rig cache hit, four missing-output invalidations, DFF/model-TXD/global-TXD changes, stale signature; fixtures remain at',root);
}
main();
