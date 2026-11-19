#!/usr/bin/env node
// Export the archived scene builder's complete local vehicle meshes and joint
// hierarchy. Original DFF/TXD data and generated rigs remain local-only.
const fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const {spawnSync}=require('node:child_process');
const {archivedModules}=require('../../tests/vehicles/smoke_vehicle_dynamics');
const {reference:couplingReference}=require('./prepare_native_vehicle_coupling');

function rigFactory(load) {
  // Expose the existing closed-over pure rig constructor, without executing
  // the async webpage factory or its DOM, network or renderer entry points.
  const source=load.factories[62540].toString(),marker='tr=function(e,t,l,r,a,o){';
  const start=source.indexOf(marker)+3,end=source.indexOf('}(e.id,$,et,e3,$.position.y,tn.box)',start)+1;
  if(start<3||end<=start)throw Error('Archived62540 rig constructor signature changed');
  const expression=source.slice(start,end),tail=source.lastIndexOf('}');
  const patched=source.slice(0,tail)+';let nativeRig='+expression+';'+source.slice(tail);
  const exported=patched.replace('pV:()=>eD,','pV:()=>eD,nativeRig:()=>nativeRig,nativeGear:()=>E,');
  if(exported===patched)throw Error('Archived62540 export signature changed');
  const clock={value:0,now(){return this.value}};
  load.factories[62540]=Function('performance','return ('+exported+')')(clock);
  return {create:load(62540).nativeRig,gear:load(62540).nativeGear,clock,sha256:createHash('sha256').update(expression).digest('hex')};
}

function createLibrary(options={}) {
  const load=archivedModules(),sourceHash=createHash('sha256');
  for(const id of Object.keys(load.factories).sort((a,b)=>Number(a)-Number(b)))sourceHash.update(id+':'+load.factories[id].toString()+'\n');
  for(const file of [__filename,path.join(require('node:path').resolve(__dirname, '../..'),'tools/assets/prepare_native_vehicle_rig_atlas.py'),path.join(require('node:path').resolve(__dirname, '../..'),'tests/vehicles/smoke_vehicle_dynamics.js'),path.join(require('node:path').resolve(__dirname, '../..'),'tools/assets/prepare_native_vehicle_coupling.js')])sourceHash.update(fs.readFileSync(file));
  const sourceSHA256=sourceHash.digest('hex'),rig=rigFactory(load),T=load(85339),geometry=load(88711),catalogue=load(72197),coupling=couplingReference(load);
  const palette=Array.from({length:catalogue.mg},(_,index)=>{
    const hex=catalogue.W_(index);
    if(!/^#[0-9a-f]{6}$/i.test(hex))throw Error('Invalid original car palette colour');
    return [1,3,5].map(at=>parseInt(hex.slice(at,at+2),16));
  });
  const variantsSource=load.factories[72197].toString().match(/let u=JSON\.parse\('([^']*)'\)/);
  if(!variantsSource)throw Error('Original four-colour catalogue signature changed');
  const colorVariants=JSON.parse(variantsSource[1]);
  const game=options.game??path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game'),hashes=new Map(),decodedTextures=new Map();
  const filename=url=>path.join(game,url.split('/').pop());
  function inputHash(file){if(!hashes.has(file))hashes.set(file,createHash('sha256').update(fs.readFileSync(file)).digest('hex'));return hashes.get(file)}
  function signature(definition){
    const assets=catalogue.yc(catalogue.AX({id:Number(definition.id)}));
    const files=[definition.model+'.dff',...assets.txds.map(url=>url.split('/').pop()),...assets.parts.flatMap(part=>part.url?[part.url.split('/').pop()]:[])];
    const inputs=files.map(file=>({file,sha256:inputHash(path.join(game,file))}));
    return {sha256:createHash('sha256').update(JSON.stringify({version:3,sourceSHA256,assets,inputs})).digest('hex'),sourceSHA256,inputs};
  }
  function cached(definition,output,options={}){
    const base=path.join(output,definition.model+'.rig');
    if(!['.bin','.png','.json','.normals.bin'].every(suffix=>fs.existsSync(base+suffix)&&fs.statSync(base+suffix).size>0))return false;
    try{const metadata=JSON.parse(fs.readFileSync(base+'.json','utf8'));
      return metadata.version===(options.nativeTextures?3:2)&&metadata.cacheSignature===signature(definition).sha256}catch{return false}
  }
  function build(id) {
    const definition=catalogue.Wd.find(row=>Number(row.id)===Number(id));if(!definition)throw Error('Unknown vehicle '+id);
    const bytes=fs.readFileSync(path.join(game,definition.model+'.dff')),parsed=load(78315).A(bytes);
    const assets=catalogue.yc(catalogue.AX({id:Number(id)}));
    // Original62540 uses catalogue order: model dictionaries precede global
    // vehicle textures, and88711 keeps the first occurrence of each name.
    const textureSources=assets.txds.map(url=>{const file=filename(url);if(!decodedTextures.has(file))decodedTextures.set(file,load(52528).nk(fs.readFileSync(file)));return decodedTextures.get(file)});
    const textures=geometry.XC(textureSources);
    const root=geometry.yK(parsed,textures,{kind:'vehicle',damage:true,blades:true,lowDetail:true,wheels:load(90317).y(Number(id))});
    const defaultParts=assets.parts.map(part=>{
      if(!part.url)return part;
      const file=path.join(game,part.url.split('/').pop());
      return {...part,dff:load(78315).A(fs.readFileSync(file))};
    });
    geometry.u2(root,defaultParts,textures,{colors:assets.colors,wheelScale:assets.wheelScale});
    const wheels=load(74921).p(root,assets.stance),box=new T.NRn().setFromObject(root),size=box.getSize(new T.Pq0());
    root.position.y=-box.min.y;const body=new T.YJl();body.add(root);
    const table=load(87605).c_(Number(id),size).table,bounds=load(87605).BO(parsed.collision,size,root.position.y);
    load(87605).FV(Number(id),body,root,wheels);
    const motion=rig.create(Number(id),root,wheels,table,root.position.y,bounds.box);
    // Use zero-drop local wheel homes; actual suspension is supplied at run
    // time. This is the same original pose function, with explicit inputs.
    motion.pose?.(0,0,0,{drop:[0,0],lean:0,crank:0,rotor:0,spin:0,gearUp:false,nozzle:5000},[0,0,0,0]);
    const damage=load(39851).k({root,body,wheels});
    const defaults=catalogue.AX({id:Number(id)}).colors;
    const paint={version:1,vertexRGB:'neutral-paint-slot-rgb',palette,defaults,colorVariants:colorVariants[Number(id)]??[],
      customFlag:0x1000000,customLimit:0x2000000};
    const built={id:Number(id),definition,parsed,bytes,root,body,wheels,table,bounds,size,motion,damage,textures,T,geometry,rig,coupling,paint,cache:signature(definition)};
    // Prepare original working-part groups at their rest pose before exporting
    // hierarchy indices. Runtime working controls then rotate these same groups.
    coupling.prepare(built);root.updateMatrixWorld(true);return built;
  }
  return {load,build,catalogue,game,T,geometry,rig,signature,cached};
}

function exportRig(built,output,options={}) {
  const nativeTextures=options.nativeTextures===true;
  if(nativeTextures&&options.atlas===false)throw Error('Native textures require a complete atlas family');
  const {T,root,definition,motion,textures,geometry}=built,model=root.userData.model;
  model.updateMatrixWorld(true);
  const objects=[];model.traverse(object=>objects.push(object));const indices=new Map(objects.map((object,index)=>[object,index]));
  const vector=value=>[value.x,value.y,value.z],quaternion=value=>[value.x,value.y,value.z,value.w];
  const nodes=objects.map(object=>({name:object.name,parent:indices.get(object.parent)??-1,
    position:vector(object.position),rotation:quaternion(object.quaternion),scale:vector(object.scale),
    matrix:[...object.matrix.elements],matrixAutoUpdate:object.matrixAutoUpdate,visible:object.visible,
    wheel:!!object.userData.wheel,hub:object.userData.hub?.name??null,
    node:object.userData.node??null,misc:object.userData.misc??[],swivel:object.userData.swivel??null,
    damaged:!!object.userData.damaged,lowDetail:!!object.userData.vlo,extra:object.userData.extra??null}));
  const slots=new Map(),textureRows=[];
  function textureSlot(texture) {
    if(!texture)return 0;
    if(slots.has(texture))return slots.get(texture);
    const slot=textureRows.length+1,name=[...textures].find(([,candidate])=>candidate===texture)?.[0]??'unnamed';
    if(nativeTextures&&(![1000,1001,1002].includes(texture.wrapS)||![1000,1001,1002].includes(texture.wrapT)||
      ![1003,1006].includes(texture.magFilter)||![1003,1004,1005,1006,1007,1008].includes(texture.minFilter)||texture.flipY!==false||texture.format!==1023))
      throw Error('Unsupported original texture sampler '+name);
    slots.set(texture,slot);textureRows.push({name,width:texture.image.width,height:texture.image.height,
      sampler:{wrapS:texture.wrapS,wrapT:texture.wrapT,magFilter:texture.magFilter,minFilter:texture.minFilter,generateMipmaps:texture.generateMipmaps===true},
      rgba:Buffer.from(texture.image.data).toString('base64')});return slot;
  }
  const positions=[],normals=[],uvs=[],colors=[],layers=[],triangles=[],draws=[];
  for(const object of objects) {
    if(!object.isMesh||object.userData.keepsWaterOut)continue;
    const g=object.geometry,p=g.attributes.position,normal=g.attributes.normal,uv=g.attributes.uv,color=g.attributes.color,index=g.index;
    if(!p||!index)throw Error('Original vehicle mesh lacks indexed positions');
    const materials=[object.material].flat(),groups=g.groups.length?g.groups:[{start:0,count:index.count,materialIndex:0}];
    for(const group of groups) {
      const material=materials[group.materialIndex];if(!material)throw Error('Missing original material');
      const start=triangles.length,cache=new Map(),slot=textureSlot(material.map),litSlot=material.userData.lens>=0?textureSlot(textures.get('vehiclelightson128')):0;
      for(let i=group.start;i<group.start+group.count;i++) {
        const source=index.getX(i);
        if(!cache.has(source)) {
          cache.set(source,positions.length/3);positions.push(p.getX(source),p.getY(source),p.getZ(source));
          normals.push(normal?normal.getX(source):0,normal?normal.getY(source):0,normal?normal.getZ(source):0);
          uvs.push(uv?uv.getX(source):0,uv?uv.getY(source):0);layers.push(slot);
          // Never bake the instance's fallback body paint into its mesh.
          // Preserve original geometry/prelit RGB, including zero channels.
          const painted=Number.isInteger(material.userData.slot)&&material.userData.slot>=0&&material.userData.slot<4;
          const tint=painted?[1,1,1]:[material.color.r,material.color.g,material.color.b];
          for(let axis=0;axis<3;axis++)colors.push(Math.round(255*Math.min(1,Math.max(0,(color?color.array[source*color.itemSize+axis]/(color.normalized?255:1):1)*tint[axis]))));
          colors.push(Math.round(255*material.opacity));
        }
        triangles.push(cache.get(source));
      }
      draws.push({node:indices.get(object),start,count:triangles.length-start,material:group.materialIndex,
        materialVisible:material.visible,lens:material.userData.lens??-1,paint:material.userData.slot??-1,
        texture:slot,litTexture:litSlot,glass:!!material.userData.glass,alphaTest:material.alphaTest,
        color:[material.color.r,material.color.g,material.color.b],opacity:material.opacity,lighting:!!normal,
        roughness:material.roughness??null,metalness:material.metalness??null});
    }
  }
  const count=positions.length/3,textureCount=textureRows.length+1;
  const bytes=Buffer.alloc(16+count*12+count*8+triangles.length*4+count*4+count*2+(count%2?2:0)+count*4+textureCount*2);
  // Distinguish neutral painted RGB from legacy WRL2 baked material colour.
  // The native rig loader verifies this family before adapting the header.
  let at=0;for(const value of [nativeTextures?0x33435056:0x32435056,count,triangles.length,textureCount]){bytes.writeUInt32LE(value,at);at+=4}
  for(const value of positions){bytes.writeFloatLE(value,at);at+=4}for(const value of uvs){bytes.writeFloatLE(value,at);at+=4}
  for(const value of triangles){bytes.writeUInt32LE(value,at);at+=4}Buffer.from(colors).copy(bytes,at);at+=count*4;
  for(const value of layers){bytes.writeUInt16LE(value,at);at+=2}if(count%2)at+=2;Buffer.from(colors).copy(bytes,at);at+=count*4;
  if(at+textureCount*2!==bytes.length)throw Error('Invalid WRL2 output size');
  const frames=[...root.userData.frames].map(([name,matrix])=>({name,parent:root.userData.parents.get(name)??null,matrix:[...matrix.elements]}));
  const joints=loadJoints(built,objects,indices);
  const waterMasks=objects.filter(object=>object.isMesh&&object.userData.keepsWaterOut).map(object=>({
    node:indices.get(object),positions:[...object.geometry.attributes.position.array],indices:[...object.geometry.index.array]}));
  const metadata={version:nativeTextures?3:2,id:built.id,model:definition.model,kind:motion.kind,axes:'GTA DFF x,y,z; local geometry + hierarchical matrices',
    cacheSignature:options.atlas===false?null:built.cache.sha256,cacheSourceSHA256:built.cache.sourceSHA256,cacheInputs:built.cache.inputs,
    dffSHA256:createHash('sha256').update(built.bytes).digest('hex'),rigFactorySHA256:built.rig.sha256,
    origin:root.position.y,nodes,frames,draws,joints,waterMasks,textures:textureRows.map(({name,width,height},index)=>({name,width,height,layer:index+1})),
    vertices:count,indices:triangles.length,paint:built.paint,binaryEncoding:nativeTextures?'VPC3':'VPC2',
    binarySHA256:createHash('sha256').update(bytes).digest('hex'),atlasSHA256:null,normalsSHA256:null};
  fs.mkdirSync(output,{recursive:true});const base=path.join(output,definition.model+'.rig');
  fs.writeFileSync(base+'.bin.tmp',bytes,{mode:0o600});fs.renameSync(base+'.bin.tmp',base+'.bin');
  const normalBytes=Buffer.alloc(normals.length*4);normals.forEach((value,index)=>normalBytes.writeFloatLE(value,index*4));
  metadata.normalsSHA256=createHash('sha256').update(normalBytes).digest('hex');
  fs.writeFileSync(base+'.normals.bin.tmp',normalBytes,{mode:0o600});fs.renameSync(base+'.normals.bin.tmp',base+'.normals.bin');
  if(options.atlas!==false) {
    const atlas=spawnSync(process.env.PYTHON??'python3',[path.join(require('node:path').resolve(__dirname, '../..'),'tools/assets/prepare_native_vehicle_rig_atlas.py'),base+'.png',...(nativeTextures?['--native-textures']:[])],{input:JSON.stringify(textureRows),encoding:'utf8'});
    if(atlas.status!==0)throw Error('Atlas creation failed: '+atlas.stderr);
    metadata.atlasSHA256=createHash('sha256').update(fs.readFileSync(base+'.png')).digest('hex');
    if(nativeTextures){const layout=JSON.parse(atlas.stdout);
      metadata.nativeTextures={...layout,samplers:[{wrapS:1000,wrapT:1000,magFilter:1003,minFilter:1003,generateMipmaps:false},...textureRows.map(row=>row.sampler)]};}
  }
  // Publish the cache marker last, only after all geometry/atlas writes pass.
  fs.writeFileSync(base+'.json.tmp',JSON.stringify(metadata),{mode:0o600});fs.renameSync(base+'.json.tmp',base+'.json');
  geometry.xd(root,null);return metadata;
}

function loadJoints(built,objects,indices) {
  const {root,motion,T}=built,model=root.userData.model,vector=value=>[value.x,value.y,value.z],quaternion=value=>[value.x,value.y,value.z,value.w];
  const rows={damage:[],wheels:[],rotors:[],gear:[],nozzles:[]};
  const damageNodes=['bonnet_dummy','boot_dummy','door_lf_dummy','door_rf_dummy','door_lr_dummy','door_rr_dummy','wing_lf_dummy','wing_rf_dummy','windscreen_dummy','bump_front_dummy','bump_rear_dummy'];
  for(const object of objects) {
    const wheel=built.wheels.find(wheel=>wheel.mesh===object);
    if(wheel)rows.wheels.push({node:indices.get(object),hub:object.userData.hub?.name??null,home:vector(wheel.home),rest:quaternion(wheel.rest),lean:quaternion(wheel.lean),front:wheel.front,left:wheel.left,bogie:wheel.bogie});
    if(!object.isMesh&&object!==model) {
      const child=object.children.find(child=>child.isMesh&&child.userData.node&&!child.userData.wheel),part=damageNodes.indexOf(child?.userData.node);
      if(part>=0)rows.damage.push({part,node:indices.get(object),rest:quaternion(object.quaternion),hinge:vector(object.position)});
      if(object.name.startsWith('gear:')) {
        const name=object.name.slice(5),frame=root.userData.frames.get(name),parent=root.userData.parents.get(name),over=root.userData.frames.get(parent)??new T.kn4(),entry=built.rig.gear.get(built.id)?.[name];
        if(!frame||!entry)throw Error('Missing original gear joint '+name);
        rows.gear.push({node:indices.get(object),frame:name,axis:vector(entry[0]),angle:entry[1],over:[...over.elements],at:vector(new T.Pq0().setFromMatrixPosition(over.clone().invert().multiply(frame))),undo:[...frame.clone().invert().elements]});
      }
      const swivels=object.children.filter(child=>child.isMesh).map(child=>child.userData.swivel);
      if(built.id===520&&swivels.length&&swivels.every(name=>['wheel_lm_dummy','wheel_rm_dummy'].includes(name)))rows.nozzles.push({node:indices.get(object)});
    }
    if(object.isMesh&&/^(static|moving)_(rotor|prop)/.test(object.name))rows.rotors.push({node:indices.get(object),name:object.name,rest:quaternion(object.quaternion)});
  }
  if(motion.kind==='bike') {
    const findParent=name=>objects.find(object=>!object.isMesh&&object.children.some(child=>child.isMesh&&child.name.toLowerCase()===name));
    const front=findParent('wheel_front'),rear=findParent('wheel_rear'),crank=findParent('chainset');
    rows.bike={model:indices.get(model),front:indices.get(front),rear:indices.get(rear),crank:indices.get(crank)??null,
      parameters:motion.bike,hubs:motion.hubs,restDrop:motion.restDrop,
      frontWheels:front?.children.filter(child=>child.name.toLowerCase()==='wheel_front').map(child=>indices.get(child))??[],
      frontMudguards:front?.children.filter(child=>child.name.toLowerCase()==='mudguard').map(child=>indices.get(child))??[],
      rearWheels:rear?.children.filter(child=>child.name.toLowerCase()==='wheel_rear').map(child=>indices.get(child))??[],
      pedals:crank?.children.filter(child=>!child.isMesh).map(child=>indices.get(child))??[],pedalled:motion.pedalled,
      rearForkLength:Math.max(0.1,Math.hypot(motion.hubs.rear.at[1]-rear.position.y,motion.hubs.rear.at[2]-rear.position.z)),minimumZ:built.bounds.box.min[2]};
  }
  rows.rearSteerOnly=(built.table.flags??0)&32?true:false;
  const working=built.coupling.configuration(built).working;
  if(working)rows.working={tow:working.tow===true,turn:working.turn??0,lift:working.lift??0,
    parts:[...(root.userData.parts??[])].map(([role,part])=>({node:indices.get(part.group),role,rest:quaternion(part.rest),home:vector(part.group.position)}))};
  return rows;
}

function main() {
  const library=createLibrary(),ids=process.argv.slice(2).filter(arg=>!arg.startsWith('--')).map(Number);
  const definitions=process.argv.includes('--all')?library.catalogue.Wd:library.catalogue.Wd.filter(row=>ids.includes(Number(row.id)));
  if(!definitions.length)throw Error('Specify vehicle model IDs or --all');
  const output=path.join(library.game,'native/models'),failures=[];let vertices=0,reused=0,prepared=0;
  for(const definition of definitions)try {
    const nativeTextures=process.argv.includes('--native-textures');
    if(process.argv.includes('--if-needed')&&library.cached(definition,output,{nativeTextures})){reused++;continue}
    const result=exportRig(library.build(definition.id),output,{atlas:!process.argv.includes('--no-atlas'),nativeTextures});prepared++;vertices+=result.vertices;console.log(result.id,result.model,result.nodes.length+'nodes',result.draws.length+'draws',result.vertices+'vertices')}
  catch(error){failures.push({id:definition.id,error:error.stack});console.error(definition.id,error.message)}
  console.log('Prepared',prepared,'complete local vehicle rigs, reused',reused,'valid caches,',vertices,'vertices,',failures.length,'failures');
  if(failures.length)process.exitCode=1;
}
if(require.main===module)main();
module.exports={createLibrary,exportRig};
