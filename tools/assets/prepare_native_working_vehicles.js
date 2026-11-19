#!/usr/bin/env node
'use strict';
// Build complete, matched owner-local working rig families in an isolated
// stage. Never replace only metadata while retaining old mesh/atlas buffers.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {createLibrary,exportRig}=require('./prepare_native_vehicle_rigs');
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const suffixes=['.rig.bin','.rig.normals.bin','.rig.png','.rig.json'];

function validateFamily(directory,model,id,expectedSignature){
  const sha=value=>typeof value==='string'&&/^[0-9a-f]{64}$/.test(value);
  const integer=(value,min,max)=>Number.isSafeInteger(value)&&value>=min&&value<=max;
  const vector=(value,count)=>Array.isArray(value)&&value.length===count&&value.every(Number.isFinite);
  if(typeof model!=='string'||!/^[a-z0-9_]{1,64}$/.test(model)||!integer(id,0,65535)||!sha(expectedSignature))throw Error('Invalid requested rig identity/signature');
  const files={},components={},limits={'.rig.bin':128_000_000,'.rig.normals.bin':12_000_000,'.rig.png':64_000_000,'.rig.json':32_000_000};
  for(const suffix of suffixes){
    const name=model+suffix,file=path.join(directory,name),size=fs.statSync(file);
    if(!size.isFile()||size.size<=0||size.size>limits[suffix])throw Error('Invalid rig component size '+name);
    const bytes=fs.readFileSync(file);if(bytes.length!==size.size)throw Error('Rig component changed while reading '+name);
    files[name]={bytes:bytes.length,sha256:digest(bytes)};components[suffix]=bytes;
  }
  const metadata=JSON.parse(components['.rig.json'].toString('utf8')),bytes=components['.rig.bin'];
  if(![1,2].includes(metadata.version)||metadata.id!==id||metadata.model!==model||metadata.cacheSignature!==expectedSignature)throw Error('Rig identity/signature mismatch '+model);
  if(metadata.version===2){
    for(const [key,suffix]of [['binarySHA256','.rig.bin'],['atlasSHA256','.rig.png'],['normalsSHA256','.rig.normals.bin']]){
      if(!sha(metadata[key])||metadata[key]!==files[model+suffix].sha256)throw Error('Rig component hash mismatch '+model+suffix);
    }
    if(metadata.binaryEncoding!=='VPC2')throw Error('Neutral rig encoding mismatch '+model);
    const paint=metadata.paint,validColor=value=>integer(value,0,(paint?.palette?.length??0)-1)||integer(value,0x1000000,0x1ffffff);
    if(!paint||paint.version!==1||paint.vertexRGB!=='neutral-paint-slot-rgb'||paint.customFlag!==0x1000000||paint.customLimit!==0x2000000||
       !Array.isArray(paint.palette)||!integer(paint.palette.length,1,1024)||paint.palette.some(rgb=>!Array.isArray(rgb)||rgb.length!==3||rgb.some(c=>!integer(c,0,255)))||
       !Array.isArray(paint.defaults)||paint.defaults.length!==2||!paint.defaults.every(validColor)||
       !Array.isArray(paint.colorVariants)||paint.colorVariants.length>256||paint.colorVariants.some(row=>!Array.isArray(row)||row.length!==4||!row.every(validColor)))throw Error('Invalid neutral rig paint metadata '+model);
  }else if(metadata.paint!=null||(metadata.binaryEncoding!=null&&metadata.binaryEncoding!=='WRL2')){
    // Deliberate legacy support retains baked RGB. Relabelling a neutral
    // family as v1 must never bypass the new-family hashes or colour contract.
    throw Error('Legacy rig contains neutral paint metadata '+model);
  }
  if(!integer(metadata.vertices,1,999999)||!integer(metadata.indices,3,2999999)||metadata.indices%3!==0||
     !Array.isArray(metadata.textures)||metadata.textures.length>=1024||metadata.textures.some((row,index)=>!row||row.layer!==index+1||!integer(row.width,1,16384)||!integer(row.height,1,16384)))throw Error('Invalid rig buffer counts/textures '+model);
  if(bytes.length<16||bytes.readUInt32LE(0)!==(metadata.version===2?0x32435056:0x324c5257)||bytes.readUInt32LE(4)!==metadata.vertices||bytes.readUInt32LE(8)!==metadata.indices||bytes.readUInt32LE(12)!==metadata.textures.length+1)throw Error('Rig binary/metadata mismatch '+model);
  const n=metadata.vertices,i=metadata.indices,t=metadata.textures.length+1,indexAt=16+n*20,colorAt=indexAt+i*4,layerAt=colorAt+n*4;
  const expected=16+n*12+n*8+i*4+n*4+n*2+(n%2?2:0)+n*4+t*2,normals=components['.rig.normals.bin'];
  if(bytes.length!==expected||normals.length!==n*12)throw Error('Truncated rig buffers '+model);
  for(let at=16;at<indexAt;at+=4)if(!Number.isFinite(bytes.readFloatLE(at)))throw Error('Nonfinite rig position/UV '+model);
  for(let at=0;at<normals.length;at+=4)if(!Number.isFinite(normals.readFloatLE(at)))throw Error('Nonfinite rig normal '+model);
  for(let at=indexAt;at<colorAt;at+=4)if(bytes.readUInt32LE(at)>=n)throw Error('Invalid rig vertex index '+model);
  for(let vertex=0;vertex<n;vertex++)if(bytes.readUInt16LE(layerAt+vertex*2)>=t)throw Error('Invalid rig texture layer '+model);
  if(!Array.isArray(metadata.nodes)||!integer(metadata.nodes.length,1,4095)||metadata.nodes.some((node,index)=>!node||!integer(node.parent,-1,index-1)||!vector(node.position,3)||!vector(node.rotation,4)||!vector(node.scale,3)||!vector(node.matrix,16))||
     !Array.isArray(metadata.draws)||metadata.draws.length>50000||metadata.draws.some(draw=>!draw||!integer(draw.node,0,metadata.nodes.length-1)||!integer(draw.start,0,i)||!integer(draw.count,0,i-draw.start)||draw.start%3!==0||draw.count%3!==0||
       !integer(draw.texture,0,t-1)||!integer(draw.litTexture,0,t-1)||!Number.isFinite(draw.alphaTest)||draw.alphaTest<0||draw.alphaTest>1||
       (metadata.version===2&&(!integer(draw.paint,-1,3)||!vector(draw.color,3)||draw.color.some(v=>v<0||v>1)))))throw Error('Invalid hierarchy/draw ranges '+model);
  const png=components['.rig.png'];
  if(png.length<33||!png.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))||png.readUInt32BE(8)!==13||png.subarray(12,16).toString()!=='IHDR'||png.readUInt32BE(16)!==1024||png.readUInt32BE(20)!==Math.ceil(t/8)*128)throw Error('Rig atlas mismatch '+model);
  const working=metadata.joints?.working;
  if(!working||typeof working.tow!=='boolean'||!Number.isFinite(working.turn)||!Number.isFinite(working.lift)||!Array.isArray(working.parts)||working.parts.length>32768||
     working.parts.some(part=>!part||!integer(part.node,0,metadata.nodes.length-1)||typeof part.role!=='string'||part.role.length>64||!vector(part.rest,4)||!vector(part.home,3)))throw Error('Invalid working rig metadata '+model);
  return {id,model,workingParts:metadata.joints.working.parts.length,files};
}

function safeOutput(output){
  const local=path.resolve(require('node:path').resolve(__dirname, '../..'),'local-only'),relative=path.relative(local,output);
  if(relative===''||relative==='..'||relative.startsWith('..'+path.sep)||path.isAbsolute(relative))throw Error('Working rigs must stay under this project local-only directory');
  function status(file){try{return fs.lstatSync(file)}catch(error){if(error.code==='ENOENT')return null;throw error}}
  let current=local;
  for(const part of relative.split(path.sep)){if(status(current)?.isSymbolicLink())throw Error('Refusing shared output ancestor '+current);current=path.join(current,part)}
  const info=status(current);if(info?.isSymbolicLink())throw Error('Refusing shared output link');
  if(info&&!info.isDirectory())throw Error('Working stage output must be a directory');
}

function main(){
  const args=process.argv.slice(2),at=args.indexOf('--output');if(at>=0&&!args[at+1])throw Error('--output requires a directory');
  const output=path.resolve(at>=0?args[at+1]:path.join(require('node:path').resolve(__dirname, '../..'),'local-only/native-working/models'));safeOutput(output);
  const catalog=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/selfhost/coupling-catalog.json'),'utf8'));
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
