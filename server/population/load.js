// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const fs=require('node:fs'),path=require('node:path');
const {PedestrianPaths}=require('./pedestrian_paths');
const {Pedestrians}=require('./pedestrians');
module.exports=function load(root,{ground,clear}){
 const bounded=(file,maximum)=>{const fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);try{
  const before=fs.fstatSync(fd);if(!before.isFile()||before.size>maximum)throw Error('Population resource size/type');
  const data=fs.readFileSync(fd),after=fs.fstatSync(fd);
  if(data.length!==before.size||after.size!==before.size||after.mtimeMs!==before.mtimeMs)throw Error('Population resource changed');return data;
 }finally{fs.closeSync(fd);}};
 const config=JSON.parse(bounded(path.join(root,'local-only/selfhost/population.json'),65536));
 if(config.version!==1||config.profile!=='zgta-original-pavement-population-v1'||typeof config.pathsCRC32!=='string')throw Error('Population profile');
 const graph=new PedestrianPaths(bounded(path.join(root,'local-only/site/game/world/paths.bin'),3*1024*1024),config.pathsCRC32);
 return new Pedestrians({graph,models:config.models,ground,clear,maximum:config.maximum??64,perObserver:config.perObserver??12});
};
