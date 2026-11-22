#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual local population loader. These invented files exercise source-family
// admission, not native bind pose, image decode, animation or rendered actors.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const ROOT=path.resolve(__dirname,'../..'),load=require(process.argv[2]?path.resolve(process.argv[2]):'../../server/population/load');
const {crc32}=require('../../server/population/pedestrian_paths');
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-population-admission-'));let checks=0;
const check=(fn,why)=>{checks++;assert.throws(fn,undefined,why);};
const write=(name,bytes)=>{const file=path.join(fixture,'local-only/site',name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);};
const profile=path.join(fixture,'local-only/selfhost/population.json');fs.mkdirSync(path.dirname(profile),{recursive:true});
const graph=Buffer.alloc(56);[0x44504453,1,1,0].forEach((v,i)=>graph.writeUInt32LE(v,i*4));write('game/world/paths.bin',graph);
const config={version:1,profile:'zgta-original-pavement-population-v1',pathsCRC32:crc32(graph),models:[7]};
const save=()=>fs.writeFileSync(profile,JSON.stringify(config));save();
const start=()=>load(fixture,{ground:()=>0,clear:()=>true});
try{
 check(start,'A bare model ID with no prepared assets admitted invisible NPCs');
 write('game/native/models/index.json','{"peds":{"7":"invented"}}');
 for(const suffix of ['.bin','.png','.skel.bin'])write('game/native/models/invented'+suffix,Buffer.alloc(0));
 check(start,'Empty model files admitted invisible NPCs');
 const family=JSON.parse(execFileSync('python3',[path.join(ROOT,'tests/resources/population_model_fixture.py')],{encoding:'utf8',timeout:5000})).map(b=>Buffer.from(b,'base64'));
 const paths=['game/native/models/invented.bin','game/native/models/invented.png','game/native/models/invented.skel.bin'];paths.forEach((p,i)=>write(p,family[i]));
 const legacy=start();checks++;assert.deepEqual(legacy.models,[7]);assert.equal(legacy.actors.size,0);
 const indexPath=path.join(fixture,'local-only/site/game/native/models/index.json');
 fs.renameSync(indexPath,indexPath+'.owned');fs.symlinkSync(path.basename(indexPath)+'.owned',indexPath);
 checks++;assert.deepEqual(start().models,[7],'Owner-local prepared index aliases must remain supported');
 for(let i=0;i<3;i++){write(paths[i],Buffer.from('invalid'));check(start,'Corrupt model family member was admitted');write(paths[i],family[i]);}
 const mismatch=Buffer.from(family[2]);mismatch.writeUInt32LE(4,4);write(paths[2],mismatch);check(start,'Mesh and skeletal vertex counts disagree');write(paths[2],family[2]);
 const hashes=Object.fromEntries(['game/native/models/index.json','game/world/paths.bin',...paths].map(p=>[p,crypto.createHash('sha256').update(fs.readFileSync(path.join(fixture,'local-only/site',p))).digest('hex')]));
 config.sourceHashes=hashes;save();checks++;assert.deepEqual(start().models,[7]);
 const recolored=Buffer.from(family[0]);recolored[88]=0;write(paths[0],recolored);check(start,'A structurally valid changed source bypassed its prepared identity');write(paths[0],family[0]);
 for(const bad of [null,[],{}, {...hashes,'../outside':'0'.repeat(64)}, {...hashes,[paths[1]]:'0'.repeat(64)}]){
  config.sourceHashes=bad;save();check(start,'Invalid/missing/excess source identities admitted a profile');
 }
 config.sourceHashes=hashes;save();write('game/native/models/index.json','{"peds":{"7":"other"}}');check(start,'Changed index borrowed earlier model admission');
 console.log(`PASS ${checks} actual population loader admission checks; invented family only, no GPU/animation/retail claim`);
}finally{fs.rmSync(fixture,{recursive:true,force:true});}
