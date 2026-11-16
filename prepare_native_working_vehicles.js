#!/usr/bin/env node
'use strict';
// Build complete, matched owner-local working rig families in an isolated
// stage. Never replace only metadata while retaining old mesh/atlas buffers.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {createLibrary,exportRig}=require('./prepare_native_vehicle_rigs');
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const suffixes=['.rig.bin','.rig.normals.bin','.rig.png','.rig.json'];

function validateFamily(directory,model,id,expectedSignature){
  const files={};for(const suffix of suffixes){const name=model+suffix,bytes=fs.readFileSync(path.join(directory,name));if(!bytes.length)throw Error('Empty rig component '+name);files[name]={bytes:bytes.length,sha256:digest(bytes)}}
  const metadata=JSON.parse(fs.readFileSync(path.join(directory,model+'.rig.json'),'utf8')),bytes=fs.readFileSync(path.join(directory,model+'.rig.bin'));
  if(metadata.version!==1||metadata.id!==id||metadata.model!==model||metadata.cacheSignature!==expectedSignature)throw Error('Rig identity/signature mismatch '+model);
  if(bytes.length<16||bytes.readUInt32LE(0)!==0x324c5257||bytes.readUInt32LE(4)!==metadata.vertices||bytes.readUInt32LE(8)!==metadata.indices||bytes.readUInt32LE(12)!==metadata.textures.length+1)throw Error('Rig binary/metadata mismatch '+model);
  const n=metadata.vertices,i=metadata.indices,t=metadata.textures.length+1,expected=16+n*12+n*8+i*4+n*4+n*2+(n%2?2:0)+n*4+t*2;
  if(bytes.length!==expected||fs.statSync(path.join(directory,model+'.rig.normals.bin')).size!==n*12)throw Error('Truncated rig buffers '+model);
  if(!metadata.nodes.length||metadata.nodes.some((node,index)=>node.parent< -1||node.parent>=index)||metadata.draws.some(draw=>draw.node<0||draw.node>=metadata.nodes.length||draw.start<0||draw.count<0||draw.start+draw.count>i))throw Error('Invalid hierarchy/draw ranges '+model);
  const png=fs.readFileSync(path.join(directory,model+'.rig.png'));
  if(!png.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))||png.length<24||png.readUInt32BE(16)!==1024||png.readUInt32BE(20)!==Math.ceil(t/8)*128)throw Error('Rig atlas mismatch '+model);
  if(!metadata.joints.working)throw Error('Missing working rig metadata '+model);
  return {id,model,workingParts:metadata.joints.working.parts.length,files};
}

function safeOutput(output){
  const local=path.resolve(__dirname,'local-only'),relative=path.relative(local,output);
  if(relative===''||relative.startsWith('..'+path.sep)||path.isAbsolute(relative))throw Error('Working rigs must stay under this project local-only directory');
  function status(file){try{return fs.lstatSync(file)}catch(error){if(error.code==='ENOENT')return null;throw error}}
  let current=local;
  for(const part of relative.split(path.sep)){if(status(current)?.isSymbolicLink())throw Error('Refusing shared output ancestor '+current);current=path.join(current,part)}
  const info=status(current);if(info?.isSymbolicLink())throw Error('Refusing shared output link');
  if(info&&!info.isDirectory())throw Error('Working stage output must be a directory');
}

function main(){
  const args=process.argv.slice(2),at=args.indexOf('--output');if(at>=0&&!args[at+1])throw Error('--output requires a directory');
  const output=path.resolve(at>=0?args[at+1]:path.join(__dirname,'local-only/native-working/models'));safeOutput(output);
  const catalog=JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/selfhost/coupling-catalog.json'),'utf8'));
  if(catalog.version!==1||!catalog.models||!Array.isArray(catalog.failures)||catalog.failures.length)throw Error('Prepare a complete owner-local coupling catalog first');
  const ids=Object.values(catalog.models).filter(row=>row.working).map(row=>row.id).sort((a,b)=>a-b);
  if(!ids.length)throw Error('No configured working vehicles in local catalog');
  const parent=path.dirname(output);fs.mkdirSync(parent,{recursive:true});
  const stage=fs.mkdtempSync(path.join(parent,'.working-stage-')),temporary=path.join(stage,'models');fs.mkdirSync(temporary);
  let backup=null,oldMoved=false,newMoved=false,manifestMoved=false;
  const manifestPath=path.join(parent,'manifest.json');
  try{
    const library=createLibrary(),models=[];
    for(const id of ids){const built=library.build(id),row=exportRig(built,temporary);models.push(validateFamily(temporary,row.model,id,row.cacheSignature))}
    const manifest={kind:'owner-local complete working rig families; do not publish',models};
    fs.writeFileSync(path.join(stage,'manifest.json'),JSON.stringify(manifest,null,2)+'\n',{mode:0o600});
    // Preserve the previous local stage so a failed replacement is reversible.
    if(fs.existsSync(output)||fs.existsSync(manifestPath)){
      const base=path.join(parent,'backups');fs.mkdirSync(base,{recursive:true});backup=fs.mkdtempSync(path.join(base,'working-'));
      if(fs.existsSync(output)){fs.renameSync(output,path.join(backup,'models'));oldMoved=true}
      if(fs.existsSync(manifestPath)){fs.renameSync(manifestPath,path.join(backup,'manifest.json'));manifestMoved=true}
    }
    fs.renameSync(temporary,output);newMoved=true;
    // The readiness manifest is last, after every matched family validates.
    fs.renameSync(path.join(stage,'manifest.json'),manifestPath);
    console.log('Prepared',models.length,'matched local working rig families,',models.length*suffixes.length,'files;',models.reduce((n,row)=>n+Object.values(row.files).reduce((s,file)=>s+file.bytes,0),0),'bytes');
    console.log('Manifest:',manifestPath);if(backup)console.log('Previous stage retained:',backup);
  }catch(error){
    if(newMoved&&fs.existsSync(output))fs.renameSync(output,path.join(stage,'failed-models'));
    if(oldMoved)fs.renameSync(path.join(backup,'models'),output);
    if(manifestMoved)fs.renameSync(path.join(backup,'manifest.json'),manifestPath);
    throw error;
  }finally{fs.rmSync(stage,{recursive:true,force:true})}
}
if(require.main===module){try{main()}catch(error){console.error(error.message);process.exitCode=1}}
module.exports={validateFamily,safeOutput};
