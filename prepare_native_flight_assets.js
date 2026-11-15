#!/usr/bin/env node
// Export the public browser's actual canopy rig and jetpack geometry. Every
// downloaded/derived asset stays under ignored local-only/site/game/.
const fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto'),{spawnSync}=require('node:child_process');
const {archivedModules}=require('./smoke_vehicle_dynamics');
async function main(){
 const game=path.join(__dirname,'local-only/site/game'),out=path.join(game,'native/models');fs.mkdirSync(out,{recursive:true});
 const required=['parachute.dff','paracx.txd','jetpack.dff','jetpack.txd'];
 for(const name of required)if(!fs.existsSync(path.join(game,name))){
  if(!process.argv.includes('--archive-missing'))throw Error('Missing original '+name+'; use --archive-missing to retain the public asset locally');
  const result=spawnSync('python3',['-c',"import pathlib,sys,urllib.request;p=pathlib.Path(sys.argv[1]);r=urllib.request.Request('https://play.samp.directory/game/'+p.name,headers={'User-Agent':'ZGTA-SA-local-archive/1.0'});d=urllib.request.urlopen(r,timeout=30).read(20000001);assert 12<len(d)<=20000000 and d[:1]!=b'<';p.write_bytes(d);p.chmod(0o600)",path.join(game,name)],{stdio:'inherit'});if(result.status!==0)throw Error('Unable to archive '+name);
 }
 const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 g.setTimeout=(f,ms)=>{const timer=setTimeout(f,ms);timer.unref();return timer};
 g.fetch=async url=>{const data=fs.readFileSync(path.join(__dirname,'local-only/site',String(url).split('?')[0]));return{ok:true,json:async()=>JSON.parse(data),arrayBuffer:async()=>{const a=new Bytes(data.length);a.set(data);return a.buffer}}};
 const api=load(49368),T=load(85339),canopy=await api.gp('parachute','paracx');
 const geometry=load(88711),textures=geometry.XC([load(52528).nk(fs.readFileSync(path.join(game,'jetpack.txd')))]);
 const jet=geometry.yK(load(78315).A(fs.readFileSync(path.join(game,'jetpack.dff'))),textures,{kind:'object'}).userData.model;
 const models={};
 for(const[name,root,ped]of[['parachute',canopy.figure,canopy],['jetpack',jet,null]]){
  root.updateMatrixWorld(true);const objects=[];root.traverse(o=>{if(o!==root||!ped)objects.push(o)});const byObject=new Map(objects.map((o,i)=>[o,i]));
  const ids=new Map(ped?[...ped.bones].map(([id,o])=>[o,id]):[]),slots=new Map,textureRows=[],positions=[],uvs=[],colors=[],layers=[],indices=[],skin=[],draws=[];
  const textureSlot=texture=>{if(!texture)return 0;if(slots.has(texture))return slots.get(texture);const slot=textureRows.length+1;slots.set(texture,slot);textureRows.push({width:texture.image.width,height:texture.image.height,rgba:Buffer.from(texture.image.data).toString('base64')});return slot};
  let skeleton=null;
  for(const object of objects){if(!object.isMesh)continue;const geom=object.geometry,p=geom.attributes.position,uv=geom.attributes.uv,color=geom.attributes.color,index=geom.index,materials=[object.material].flat();if(!index||!p)throw Error('Missing indexed flight mesh');
   if(ped){if(skeleton&&skeleton!==object.skeleton)throw Error('Canopy has multiple skin palettes');skeleton=object.skeleton}
   for(const group of geom.groups.length?geom.groups:[{start:0,count:index.count,materialIndex:0}]){const material=materials[group.materialIndex],slot=textureSlot(material.map),cache=new Map,start=indices.length;
    for(let offset=group.start;offset<group.start+group.count;offset++){const source=index.getX(offset);if(!cache.has(source)){cache.set(source,positions.length/3);positions.push(p.getX(source),p.getY(source),p.getZ(source));uvs.push(uv?.getX(source)??0,uv?.getY(source)??0);layers.push(slot);for(let axis=0;axis<3;axis++)colors.push(Math.round(255*Math.max(0,Math.min(1,(color?color.array[source*color.itemSize+axis]/(color.normalized?255:1):1)*[material.color.r,material.color.g,material.color.b][axis]))));colors.push(Math.round(255*material.opacity));if(ped){const b=geom.attributes.skinIndex,w=geom.attributes.skinWeight;skin.push({source,point:[p.getX(source),p.getY(source),p.getZ(source)],bones:[b.getX(source),b.getY(source),b.getZ(source),b.getW(source)],weights:[w.getX(source),w.getY(source),w.getZ(source),w.getW(source)]})}}
     indices.push(cache.get(source));
    }draws.push({node:byObject.get(object),start,count:indices.length-start,visible:material.visible,alphaTest:material.alphaTest});
   }
  }
  const count=positions.length/3,textureCount=textureRows.length+1,bytes=Buffer.alloc(16+count*12+count*8+indices.length*4+count*4+count*2+(count%2?2:0)+count*4+textureCount*2);let at=0;
  for(const value of[0x324c5257,count,indices.length,textureCount]){bytes.writeUInt32LE(value,at);at+=4}for(const v of positions){bytes.writeFloatLE(v,at);at+=4}for(const v of uvs){bytes.writeFloatLE(v,at);at+=4}for(const v of indices){bytes.writeUInt32LE(v,at);at+=4}Buffer.from(colors).copy(bytes,at);at+=count*4;for(const v of layers){bytes.writeUInt16LE(v,at);at+=2}if(count%2)at+=2;Buffer.from(colors).copy(bytes,at);
  fs.writeFileSync(path.join(out,name+'.bin'),bytes,{mode:0o600});
  const atlas=spawnSync(process.env.PYTHON??'python3',[path.join(__dirname,'prepare_native_vehicle_rig_atlas.py'),path.join(out,name+'.png')],{input:JSON.stringify(textureRows),encoding:'utf8'});if(atlas.status!==0)throw Error(atlas.stderr);
  const nodes=objects.map(o=>({name:o.name,parent:byObject.get(o.parent)??-1,matrix:[...o.matrix.elements]}));
  if(ped){const chunks=[],u32=v=>{const b=Buffer.alloc(4);b.writeUInt32LE(v);chunks.push(b)},i32=v=>{const b=Buffer.alloc(4);b.writeInt32LE(v);chunks.push(b)},f32=v=>{const b=Buffer.alloc(4);b.writeFloatLE(v);chunks.push(b)},matrix=m=>m.forEach(f32);chunks.push(Buffer.from('SKN1'));u32(count);u32(objects.length);u32(skeleton.bones.length);matrix(new T.kn4().elements);matrix(new T.kn4().elements);
   for(const o of objects){i32(byObject.get(o.parent)??-1);i32(ids.get(o)??-1);matrix(o.matrix.elements)}for(let i=0;i<skeleton.bones.length;i++){u32(byObject.get(skeleton.bones[i]));matrix(skeleton.boneInverses[i].elements)}for(const vertex of skin){vertex.point.forEach(f32);chunks.push(Buffer.from(vertex.bones));vertex.weights.forEach(f32)}fs.writeFileSync(path.join(out,name+'.skel.bin'),Buffer.concat(chunks),{mode:0o600});
  }
  models[name]={vertices:count,indices:indices.length,nodes,draws,skinned:!!ped,...ped?{order:skin.map(x=>x.source)}:{}};fs.writeFileSync(path.join(out,name+'.flight.json'),JSON.stringify(models[name]),{mode:0o600});
 }
 const hashes=Object.fromEntries(required.map(name=>[name,createHash('sha256').update(fs.readFileSync(path.join(game,name))).digest('hex')]));fs.writeFileSync(path.join(game,'native/flight-assets.json'),JSON.stringify({version:1,models,sources:hashes})+'\n',{mode:0o600});
 console.log('Prepared original canopy '+models.parachute.vertices+' vertices/31 bones and jetpack '+models.jetpack.vertices+' vertices locally');canopy.dispose();
}
if(require.main===module)main().catch(error=>{console.error(error.stack);process.exitCode=1});
module.exports={main};
