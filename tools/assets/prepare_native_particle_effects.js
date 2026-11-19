#!/usr/bin/env node
// Preserve the original FX texture-array dimensions, layers, sRGB space and
// sampling settings. All decoded image bytes stay in ignored local-only/.
const fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const {archivedModules}=require('../../tests/vehicles/smoke_vehicle_dynamics');
function main(){
 const game=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game'),out=path.join(game,'native/effects'),load=archivedModules(),bytes=fs.readFileSync(path.join(game,'effectspc.txd'));
 const textures=load(88711).XC([load(52528).nk(bytes)]),groups=new Map,sprites={};
 for(const[name,texture]of textures){const{data,width,height}=texture.image??{};if(!data||data.length!==width*height*4)continue;const key=width+'x'+height+' '+texture.colorSpace;
  if(!groups.has(key)){if(groups.size>=8)continue;groups.set(key,{width,height,colorSpace:texture.colorSpace,magFilter:texture.magFilter,minFilter:texture.minFilter,generateMipmaps:texture.generateMipmaps,anisotropy:texture.anisotropy,layers:[],names:[]})}
  const group=groups.get(key);sprites[name]={sheet:[...groups.keys()].indexOf(key),layer:group.layers.length};group.layers.push(Buffer.from(data));group.names.push(name);
 }
 fs.mkdirSync(out,{recursive:true});const sheets=[...groups.values()].map((group,index)=>{const file='fx-sheet-'+index+'.rgba';fs.writeFileSync(path.join(out,file),Buffer.concat(group.layers),{mode:0o600});const{layers,...metadata}=group;return{...metadata,layers:layers.length,file}});
 fs.writeFileSync(path.join(out,'fx-textures.json'),JSON.stringify({version:1,sheets,sprites,source:{'effectspc.txd':createHash('sha256').update(bytes).digest('hex')}})+'\n',{mode:0o600});
 console.log(`Prepared ${Object.keys(sprites).length} original FX textures in ${sheets.length} exact-size native arrays locally`);
}
if(require.main===module){try{main()}catch(error){console.error(error.stack);process.exitCode=1}}
module.exports={main};
