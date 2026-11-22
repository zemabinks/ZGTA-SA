// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const {square}=require('./traffic_fixture'),{crc32}=require('../../server/population/pedestrian_paths'),load=require(process.argv[2]?path.resolve(process.argv[2]):'../../server/population/load_traffic');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-traffic-loader-')),site=path.join(temporary,'local-only/site');let checks=0;
try{
 const dff=crypto.createHash('sha256').update('authored original-source boundary').digest('hex');
 const files={'game/world/roads.bin':square(),'game/native/models/index.json':Buffer.from('{"vehicles":{"410":"authored_car"}}'),
  'game/native/vehicles.physics.json':Buffer.from(JSON.stringify({models:{410:{id:410,model:'authored_car',kind:'car',dffSHA256:dff,bounds:{box:{min:[-1,-2,-.5],max:[1,2,1]}}},414:{bounds:{box:{min:[-2,-12,-1],max:[2,4,2]}}}}})),
  'game/native/models/authored_car.rig.json':Buffer.from(JSON.stringify({version:2,id:410,model:'authored_car',kind:'car',dffSHA256:dff}))};
 for(const [name,bytes]of Object.entries(files)){const file=path.join(site,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);}
 const config={version:1,profile:'zgta-prepared-road-traffic-v1',roadsCRC32:crc32(files['game/world/roads.bin']),maximum:1,perObserver:1,
  models:[{id:410,length:4,width:2,colors:[[1,2]]}],sourceHashes:Object.fromEntries(Object.entries(files).map(([n,b])=>[n,crypto.createHash('sha256').update(b).digest('hex')]))};
 for(const suffix of ['.rig.bin','.rig.png','.bin','.png'])fs.writeFileSync(path.join(site,'game/native/models/authored_car'+suffix),'authored presence only, not actual mesh/image');
 const folder=path.join(temporary,'local-only/selfhost');fs.mkdirSync(folder);const file=path.join(folder,'traffic.json');
 const write=value=>fs.writeFileSync(file,JSON.stringify(value)),dependencies={ground:()=>13,clear:()=>true,random:()=>.1};
 write(config);const traffic=load(temporary,dependencies);traffic.tick(0,[[0,0,13]]);assert.equal(traffic.actors.size,1);checks++;
 assert.deepEqual(traffic.dimensionsFor(414),{id:414,width:4,length:16,centre:[0,-4]});checks++;
 assert(Object.isFrozen(traffic.dimensionsFor(414))&&Object.isFrozen(traffic.dimensionsFor(414).centre));checks++;
 write({...config,models:[{...config.models[0],length:5}]});assert.throws(()=>load(temporary,dependencies),/bounds do not match/);checks++;
 for(const broken of [{...config,profile:'unverified'},{...config,roadsCRC32:'00000000'},{...config,sourceHashes:{}},
  {...config,sourceHashes:{...config.sourceHashes,'../../private-file':'0'.repeat(64)}}]){write(broken);assert.throws(()=>load(temporary,dependencies));checks++;}
 write(config);fs.appendFileSync(path.join(site,'game/native/models/index.json'),' ');assert.throws(()=>load(temporary,dependencies),/source changed/);checks++;
 // Presence is not GPU decoding, but selected files must still exist when
 // the server admits the profile, rather than only during earlier preparation.
 fs.writeFileSync(path.join(site,'game/native/models/index.json'),files['game/native/models/index.json']);write(config);
 for(const suffix of ['.rig.bin','.rig.png','.bin','.png']){
  const name=path.join(site,'game/native/models/authored_car'+suffix),original=fs.readFileSync(name);fs.unlinkSync(name);
  assert.throws(()=>load(temporary,dependencies),undefined,'Traffic loader admitted a selected model whose prepared mesh/image was removed');checks++;fs.writeFileSync(name,original);
 }
 function rejectMetadata(name,change,message){
  const original=files[name],value=JSON.parse(original);change(value);const bytes=Buffer.from(JSON.stringify(value));fs.writeFileSync(path.join(site,name),bytes);
  write({...config,sourceHashes:{...config.sourceHashes,[name]:crypto.createHash('sha256').update(bytes).digest('hex')}});
  assert.throws(()=>load(temporary,dependencies),undefined,message);checks++;fs.writeFileSync(path.join(site,name),original);write(config);
 }
 rejectMetadata('game/native/vehicles.physics.json',value=>{value.models['410'].kind='boat';},'Traffic loader admitted a non-road model');
 rejectMetadata('game/native/models/index.json',value=>{value.vehicles['410']='different_car';},'Traffic loader ignored indexed model identity');
 rejectMetadata('game/native/models/authored_car.rig.json',value=>{value.dffSHA256='0'.repeat(64);},'Traffic loader admitted a rig from a different model source');
 const other='game/native/models/unrelated.rig.json',otherBytes=Buffer.from('{"authored":true}');fs.writeFileSync(path.join(site,other),otherBytes);
 const hashes={...config.sourceHashes,[other]:crypto.createHash('sha256').update(otherBytes).digest('hex')};delete hashes['game/native/models/authored_car.rig.json'];write({...config,sourceHashes:hashes});
 assert.throws(()=>load(temporary,dependencies),undefined,'Traffic loader admitted a selected rig without a source identity');checks++;
 console.log('PASS traffic production profile loader '+checks+' checks; authored files, not original asset or App acceptance');
}finally{fs.rmSync(temporary,{recursive:true,force:true});}
