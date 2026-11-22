// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {TrafficRoads}=require('./traffic_roads'),{Traffic}=require('./traffic');
module.exports=function loadTraffic(root,dependencies){
 const read=(file,maximum)=>{
  const fd=fs.openSync(fs.realpathSync(file),fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);
  try{
   const before=fs.fstatSync(fd);if(!before.isFile()||before.size>maximum)throw Error('Traffic resource byte/type budget');
   const bytes=fs.readFileSync(fd),after=fs.fstatSync(fd);
   if(bytes.length!==before.size||after.size!==before.size||after.mtimeMs!==before.mtimeMs||after.ino!==before.ino)throw Error('Traffic resource changed');return bytes;
  }finally{fs.closeSync(fd);}
 };
 const config=JSON.parse(read(path.join(root,'local-only/selfhost/traffic.json'),256*1024));
 if(config.version!==1||config.profile!=='zgta-prepared-road-traffic-v1'||typeof config.roadsCRC32!=='string')throw Error('Traffic profile');
 const hashes=config.sourceHashes;let physics,index;const rigs=new Map();
 if(!hashes||typeof hashes!=='object'||Array.isArray(hashes)||Object.keys(hashes).length<4||Object.keys(hashes).length>216||
    !['game/native/models/index.json','game/native/vehicles.physics.json','game/world/roads.bin'].every(name=>Object.hasOwn(hashes,name)))throw Error('Traffic source identities');
 for(const [name,hash]of Object.entries(hashes)){
  if(!/^game\/(?:world\/roads\.bin|native\/(?:vehicles\.physics\.json|models\/(?:index\.json|[a-zA-Z0-9_]{1,32}\.rig\.json)))$/.test(name)||
     typeof hash!=='string'||!/^[a-f0-9]{64}$/.test(hash))throw Error('Traffic source identity path/hash');
  const bytes=read(path.join(root,'local-only/site',name),name.endsWith('vehicles.physics.json')?64*1048576:16*1048576);
  if(crypto.createHash('sha256').update(bytes).digest('hex')!==hash)throw Error('Prepared traffic source changed; prepare a new matching profile');
  if(name==='game/native/vehicles.physics.json')physics=JSON.parse(bytes);
  else if(name==='game/native/models/index.json')index=JSON.parse(bytes);
  else if(name.endsWith('.rig.json'))rigs.set(name,JSON.parse(bytes));
 }
 if(!physics?.models||typeof physics.models!=='object'||Array.isArray(physics.models))throw Error('Traffic original vehicle bounds required');
 if(!index?.vehicles||typeof index.vehicles!=='object'||Array.isArray(index.vehicles))throw Error('Traffic prepared model index required');
 const vehicleDimensions=[];
 for(const [key,row]of Object.entries(physics.models)){
  const id=Number(key),box=row?.bounds?.box;
  if(!Number.isInteger(id)||id<400||id>611||String(id)!==key||!box||
   ![box.min,box.max].every(v=>Array.isArray(v)&&v.length===3&&v.every(Number.isFinite)))continue;
  const width=box.max[0]-box.min[0],length=box.max[1]-box.min[1];
  if(width<.05||width>200||length<.05||length>200)continue;
  vehicleDimensions.push({id,width,length,centre:[(box.max[0]+box.min[0])/2,(box.max[1]+box.min[1])/2]});
 }
 if(!Array.isArray(config.models)||!config.models.length||config.models.length>212)throw Error('Traffic model selection budget');
 const models=config.models.map(model=>{
  const shape=vehicleDimensions.find(d=>d.id===model.id);
  if(!shape||Math.abs(model.width-shape.width)>1e-6||Math.abs(model.length-shape.length)>1e-6)throw Error('Traffic model bounds do not match prepared source');
  const row=physics.models[String(model.id)],name=index.vehicles[String(model.id)];
  if(typeof name!=='string'||!/^[a-zA-Z0-9_]{1,32}$/.test(name)||
     row.id!==model.id||row.model!==name||row.kind!=='car'||typeof row.dffSHA256!=='string'||!(/^[a-f0-9]{64}$/).test(row.dffSHA256))throw Error('Traffic selected road model identity');
  const rig=rigs.get('game/native/models/'+name+'.rig.json');
  if(!rig||![2,3].includes(rig.version)||rig.id!==model.id||rig.model!==name||rig.kind!=='car'||rig.dffSHA256!==row.dffSHA256)throw Error('Traffic selected rig source identity');
  // A valid old profile cannot keep admitting invisible cars after a required
  // asset is removed. This checks presence/type, not GPU or image decoding.
  for(const suffix of ['.rig.bin','.rig.png','.bin','.png']){
   const fd=fs.openSync(fs.realpathSync(path.join(root,'local-only/site/game/native/models',name+suffix)),fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);
   try{const stat=fs.fstatSync(fd);if(!stat.isFile()||stat.size<=0)throw Error('Traffic selected model file unavailable');}
   finally{fs.closeSync(fd);}
  }
  return {...model,centre:shape.centre};
 });
 const graph=new TrafficRoads(read(path.join(root,'local-only/site/game/world/roads.bin'),8*1048576),config.roadsCRC32);
 return new Traffic({graph,models,vehicleDimensions,maximum:config.maximum??32,perObserver:config.perObserver??6,...dependencies});
};
