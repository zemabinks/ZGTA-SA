#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Offline primary material/palette oracle and complete owner-local v2 families.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {createLibrary,exportRig}=require('./prepare_native_vehicle_rigs');
const root=__dirname,research=path.join(root,'local-only/research/vehicle-paint-105');
const output=path.join(research,'overlay/game/native/models');
const hash=data=>crypto.createHash('sha256').update(data).digest('hex');
const check=(value,message)=>{if(!value)throw Error(message);checks++;};
let checks=0,vertices=0,painted=0,nonpainted=0,paintLens=0,paintGlass=0;
function main(){
 fs.mkdirSync(output,{recursive:true});
 const library=createLibrary(),catalogue=library.catalogue,T=library.T;
 const models=[],families=[],legacyDifferences=[];
 const served=(model,suffix)=>{const working=path.join(root,'local-only/native-working/models',model+'.rig');return ['.bin','.png','.json','.normals.bin'].every(ext=>fs.existsSync(working+ext))?working+suffix:path.join(library.game,'native/models',model+'.rig'+suffix)};
 for(const definition of catalogue.Wd){
  const built=library.build(definition.id),objects=[],groups=[];
  built.root.userData.model.traverse(object=>objects.push(object));
  for(const object of objects){
   if(!object.isMesh||object.userData.keepsWaterOut)continue;
   const geometry=object.geometry,materials=[object.material].flat();
   for(const group of geometry.groups.length?geometry.groups:[{start:0,count:geometry.index.count,materialIndex:0}]){
    const material=materials[group.materialIndex];
    groups.push({object,group,material,color:material.color.clone(),opacity:material.opacity,slot:material.userData.slot??-1});
   }
  }
  const byMaterial=new Map(groups.map(row=>[row.material,row.color.clone()]));
  const id=Number(definition.id),specifications=[
   {code:String(id)},{code:`${id}.6.1.0.`},{code:`${id}.1.6.0.`},{code:`${id}.0.0.0.`},
   {code:`${id}.255.255.0.`},{code:`${id}.16777216.33554431.0.`},
   {code:`${id}.33488896.16777471.0.`},{code:`${id}..1.0.`},
   {code:`${id}.-1.999.0.`},{code:`${id}.0x06.1e0.0.`},{code:`${id}.Infinity.NaN.0.`},
   {code:`${id}.6.1.0.`,scorched:true}
  ],cases=[];
  for(const row of built.paint.colorVariants)specifications.push({code:`${id}.${row[0]}.${row[1]}.0.`});
  for(const test of specifications){
   built.damage.scorch(false);
   const options=catalogue.Yc(test.code),assets=catalogue.yc(options);
   library.geometry.Tr(built.root,assets.colors);built.damage.scorch(!!test.scorched);
   const slots={};
   for(const row of groups){
    const actual=row.material.color.toArray();
    if(row.slot>=0){
     if(slots[row.slot])check(actual.every((v,i)=>Math.abs(v-slots[row.slot][i])<1e-12),'Source material slot disagrees '+id);
     else slots[row.slot]=actual;
    }else{
     const expected=row.color.toArray().map(value=>value*(test.scorched ? .14 : 1));
     check(actual.every((v,i)=>Math.abs(v-expected[i])<1e-12),'Original repaint changed nonpaint material '+id);
    }
    check(row.material.opacity===row.opacity,'Original repaint changed opacity '+id);
   }
   cases.push({code:test.code,scorched:!!test.scorched,colors:options.colors,slots});
  }
  built.damage.scorch(false);for(const[material,color]of byMaterial)material.color.copy(color);
  const metadata=exportRig(built,output),base=path.join(output,definition.model+'.rig');
  check(metadata.version===2&&metadata.binaryEncoding==='VPC2','Unmarked neutral family');
  check(metadata.draws.length===groups.length,'Draw/material order mismatch '+id);
  const bytes=fs.readFileSync(base+'.bin'),old=fs.readFileSync(served(definition.model,'.bin')),stored=fs.readFileSync(path.join(library.game,'native/models',definition.model+'.rig.bin'));
  if(!old.equals(stored))legacyDifferences.push({id,model:definition.model,servedSHA256:hash(old),storedSHA256:hash(stored)});
  const count=bytes.readUInt32LE(4),indexCount=bytes.readUInt32LE(8),indexAt=16+count*20,colorAt=indexAt+indexCount*4;
  const duskAt=colorAt+count*4+count*2+(count%2?2:0),allowed=new Uint8Array(bytes.length);
  check(bytes.subarray(0,4).toString()==='VPC2'&&old.length===bytes.length,'Rig family shape mismatch '+id);
  for(let i=0;i<4;i++)allowed[i]=1;
  for(let part=0;part<groups.length;part++){
   const row=groups[part],draw=metadata.draws[part],g=row.object.geometry,p=g.attributes.position,uv=g.attributes.uv,color=g.attributes.color;
   check(draw.paint===row.slot&&draw.opacity===row.opacity,'Dropped material state '+id);
   if(row.slot>=0){painted++;if(draw.lens>=0)paintLens++;if(draw.glass)paintGlass++;}else nonpainted++;
   for(let corner=0;corner<draw.count;corner++){
    const vertex=bytes.readUInt32LE(indexAt+(draw.start+corner)*4),source=g.index.getX(row.group.start+corner);
    check(vertex<count,'Export index range '+id);
    for(let axis=0;axis<3;axis++){
     const sourcePosition=[p.getX(source),p.getY(source),p.getZ(source)][axis];
     check(bytes.readFloatLE(16+vertex*12+axis*4)===Math.fround(sourcePosition),'Changed source position '+id);
     const intrinsic=color?[color.getX(source),color.getY(source),color.getZ(source)][axis]:1;
     const tint=row.slot>=0?1:row.color.toArray()[axis];
     const expected=Math.round(255*Math.max(0,Math.min(1,intrinsic*tint)));
     check(bytes[colorAt+vertex*4+axis]===expected&&bytes[duskAt+vertex*4+axis]===expected,'Intrinsic/material RGB mismatch '+id);
     if(row.slot>=0){allowed[colorAt+vertex*4+axis]=1;allowed[duskAt+vertex*4+axis]=1;}
    }
    const alpha=Math.round(255*row.opacity);
    check(bytes[colorAt+vertex*4+3]===alpha&&bytes[duskAt+vertex*4+3]===alpha,'Changed alpha '+id);
   }
  }
  for(let at=4;at<bytes.length;at++)if(!allowed[at])check(bytes[at]===old[at],'Nonpaint/geometry byte changed '+id+' at'+at);
  check(hash(fs.readFileSync(base+'.normals.bin'))===hash(fs.readFileSync(served(definition.model,'.normals.bin'))),'Changed served normals '+id);
  check(hash(fs.readFileSync(base+'.png'))===hash(fs.readFileSync(served(definition.model,'.png'))),'Changed atlas '+id);
  const parts=metadata.draws.map(draw=>({start:draw.start,count:draw.count,paint:draw.paint,color:draw.color,opacity:draw.opacity,glass:draw.glass,lens:draw.lens}));
  models.push({id,model:definition.model,cases,parts});vertices+=count;
  const files=['.bin','.png','.json','.normals.bin'].map(suffix=>{const file=base+suffix;return{path:'game/native/models/'+path.basename(file),bytes:fs.statSync(file).size,sha256:hash(fs.readFileSync(file))};});
  families.push({id,model:definition.model,files,inputs:metadata.cacheInputs});
  console.log('Verified original vehicle paint',id,definition.model,groups.length,'parts');
 }
 const palette=Array.from({length:catalogue.mg},(_,id)=>({id,rgb:new T.Q1f(catalogue.nI(id)).toArray(),css:catalogue.nI(id)}));
 const shaders=[];
 for(const paint of [0,1,6,25,255,0x1000000,0x1ff0000,0x10000ff,0x1ffffff]){
  const linear=new T.Q1f(catalogue.nI(paint));
  for(const intrinsic of [5/9,.25,1])for(const texture of [255,128])for(const scorch of [1,.14]){
   const sampled=new T.Q1f(`rgb(${texture},${texture},${texture})`);
   const color=linear.clone().multiply(sampled).multiplyScalar(Math.max(.2,intrinsic*1.8)*scorch).convertLinearToSRGB();
   shaders.push({paint,linear:linear.toArray(),intrinsic,texture,scorch,expected:color.toArray().map(value=>Math.round(Math.max(0,Math.min(1,value))*255))});
  }
 }
 fs.writeFileSync(path.join(research,'reference.json'),JSON.stringify({models,palette,shaders}));
 fs.writeFileSync(path.join(research,'manifest.json'),JSON.stringify({schema:1,encoding:'VPC2',families},null,2)+'\n');
 const report={status:'PASS',models:models.length,vertices,checks,paintedParts:painted,nonpaintedParts:nonpainted,paintLens,paintGlass,
  referenceSHA256:hash(fs.readFileSync(path.join(research,'reference.json'))),sourcePaletteEntries:palette.length,legacyCachedFamilyDifferences:legacyDifferences,
  scope:'Actual owner material factory/palette/code parser for all vehicle models; complete private families; no App/device/server action',
  limits:['Native environment lighting/reflections and advanced paintjob/pattern/finish rendering remain separate parity work']};
 fs.writeFileSync(path.join(research,'producer-report.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
}
if(require.main===module)main();
