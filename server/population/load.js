// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {PedestrianPaths}=require('./pedestrian_paths');
const {Pedestrians}=require('./pedestrians');
const {validateFamily}=require('./models');
module.exports=function load(root,{ground,clear}){
 const bounded=(file,maximum)=>{const fd=fs.openSync(fs.realpathSync(file),fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);try{
  const before=fs.fstatSync(fd);if(!before.isFile()||before.size>maximum)throw Error('Population resource size/type');
  const data=fs.readFileSync(fd),after=fs.fstatSync(fd);
  if(data.length!==before.size||after.size!==before.size||after.mtimeMs!==before.mtimeMs||after.ino!==before.ino)throw Error('Population resource changed');return data;
 }finally{fs.closeSync(fd);}};
 const config=JSON.parse(bounded(path.join(root,'local-only/selfhost/population.json'),256*1024));
 if(config.version!==1||config.profile!=='zgta-original-pavement-population-v1'||typeof config.pathsCRC32!=='string')throw Error('Population profile');
 if(!Array.isArray(config.models)||!config.models.length||config.models.length>312||
    !config.models.every(id=>Number.isInteger(id)&&id>=0&&id<=311))throw Error('Population model selection');
 const required=new Set(['game/native/models/index.json','game/world/paths.bin']);
 const hashes=config.sourceHashes;
 if(hashes!==undefined&&(!hashes||typeof hashes!=='object'||Array.isArray(hashes)))throw Error('Population source identities');
 const source=(name,budget)=>{
  const bytes=bounded(path.join(root,'local-only/site',name),budget);
  if(hashes!==undefined&&(typeof hashes[name]!=='string'||!/^[a-f0-9]{64}$/.test(hashes[name])||
     crypto.createHash('sha256').update(bytes).digest('hex')!==hashes[name]))throw Error('Population source changed; prepare a matching profile');
  return bytes;
 };
 const index=JSON.parse(source('game/native/models/index.json',1024*1024));
 if(!index?.peds||typeof index.peds!=='object'||Array.isArray(index.peds))throw Error('Population prepared model index');
 for(const id of new Set(config.models)){
  const name=index.peds[String(id)];
  if(typeof name!=='string'||!/^[a-zA-Z0-9_]{1,32}$/.test(name))throw Error('Population selected model identity');
  const files=['.bin','.png','.skel.bin'].map(suffix=>{const namePath='game/native/models/'+name+suffix;required.add(namePath);return source(namePath,64*1048576);});
  validateFamily(...files);
 }
 if(hashes!==undefined&&(Object.keys(hashes).length!==required.size||Object.keys(hashes).some(name=>!required.has(name))))throw Error('Population source identity set');
 const graph=new PedestrianPaths(source('game/world/paths.bin',3*1024*1024),config.pathsCRC32);
 return new Pedestrians({graph,models:config.models,ground,clear,maximum:config.maximum??64,perObserver:config.perObserver??12});
};
