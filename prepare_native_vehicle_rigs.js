#!/usr/bin/env node
// Export the archived scene builder's complete local vehicle meshes and joint
// hierarchy. Original DFF/TXD data and generated rigs remain local-only.
const fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const {spawnSync}=require('node:child_process');
const {archivedModules}=require('./smoke_vehicle_dynamics');

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

function createLibrary() {
  const load=archivedModules(),rig=rigFactory(load),T=load(85339),geometry=load(88711),catalogue=load(72197);
  const game=path.join(__dirname,'local-only/site/game'),globalTextures=load(52528).nk(fs.readFileSync(path.join(game,'vehicle.txd')));
  function build(id) {
    const definition=catalogue.Wd.find(row=>Number(row.id)===Number(id));if(!definition)throw Error('Unknown vehicle '+id);
    const bytes=fs.readFileSync(path.join(game,definition.model+'.dff')),parsed=load(78315).A(bytes);
    const txdPath=path.join(game,definition.model+'.txd'),textureSources=[globalTextures];
    if(fs.existsSync(txdPath))textureSources.push(load(52528).nk(fs.readFileSync(txdPath)));
    const textures=geometry.XC(textureSources),assets=catalogue.yc(catalogue.AX({id:Number(id)}));
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
    root.updateMatrixWorld(true);
    return {id:Number(id),definition,parsed,bytes,root,body,wheels,table,bounds,size,motion,damage,textures,T,geometry,rig};
  }
  return {load,build,catalogue,game,T,geometry,rig};
}

function exportRig(built,output,options={}) {
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
    slots.set(texture,slot);textureRows.push({name,width:texture.image.width,height:texture.image.height,
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
          const tint=[material.color.r,material.color.g,material.color.b];
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
  let at=0;for(const value of [0x324c5257,count,triangles.length,textureCount]){bytes.writeUInt32LE(value,at);at+=4}
  for(const value of positions){bytes.writeFloatLE(value,at);at+=4}for(const value of uvs){bytes.writeFloatLE(value,at);at+=4}
  for(const value of triangles){bytes.writeUInt32LE(value,at);at+=4}Buffer.from(colors).copy(bytes,at);at+=count*4;
  for(const value of layers){bytes.writeUInt16LE(value,at);at+=2}if(count%2)at+=2;Buffer.from(colors).copy(bytes,at);at+=count*4;
  if(at+textureCount*2!==bytes.length)throw Error('Invalid WRL2 output size');
  const frames=[...root.userData.frames].map(([name,matrix])=>({name,parent:root.userData.parents.get(name)??null,matrix:[...matrix.elements]}));
  const joints=loadJoints(built,objects,indices);
  const metadata={version:1,id:built.id,model:definition.model,kind:motion.kind,axes:'GTA DFF x,y,z; local geometry + hierarchical matrices',
    dffSHA256:createHash('sha256').update(built.bytes).digest('hex'),rigFactorySHA256:built.rig.sha256,
    origin:root.position.y,nodes,frames,draws,joints,textures:textureRows.map(({name},index)=>({name,layer:index+1})),
    vertices:count,indices:triangles.length};
  fs.mkdirSync(output,{recursive:true});const base=path.join(output,definition.model+'.rig');
  fs.writeFileSync(base+'.bin.tmp',bytes,{mode:0o600});fs.renameSync(base+'.bin.tmp',base+'.bin');
  const normalBytes=Buffer.alloc(normals.length*4);normals.forEach((value,index)=>normalBytes.writeFloatLE(value,index*4));
  fs.writeFileSync(base+'.normals.bin.tmp',normalBytes,{mode:0o600});fs.renameSync(base+'.normals.bin.tmp',base+'.normals.bin');
  fs.writeFileSync(base+'.json.tmp',JSON.stringify(metadata),{mode:0o600});fs.renameSync(base+'.json.tmp',base+'.json');
  if(options.atlas!==false) {
    const atlas=spawnSync(process.env.PYTHON??'python3',[path.join(__dirname,'prepare_native_vehicle_rig_atlas.py'),base+'.png'],{input:JSON.stringify(textureRows),encoding:'utf8'});
    if(atlas.status!==0)throw Error('Atlas creation failed: '+atlas.stderr);
  }
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
  return rows;
}

function main() {
  const library=createLibrary(),ids=process.argv.slice(2).filter(arg=>!arg.startsWith('--')).map(Number);
  const definitions=process.argv.includes('--all')?library.catalogue.Wd:library.catalogue.Wd.filter(row=>ids.includes(Number(row.id)));
  if(!definitions.length)throw Error('Specify vehicle model IDs or --all');
  const output=path.join(library.game,'native/models'),failures=[];let vertices=0;
  for(const definition of definitions)try {const result=exportRig(library.build(definition.id),output,{atlas:!process.argv.includes('--no-atlas')});vertices+=result.vertices;console.log(result.id,result.model,result.nodes.length+'nodes',result.draws.length+'draws',result.vertices+'vertices')}
  catch(error){failures.push({id:definition.id,error:error.stack});console.error(definition.id,error.message)}
  console.log('Prepared',definitions.length-failures.length,'complete local vehicle rigs,',vertices,'vertices,',failures.length,'failures');
  if(failures.length)process.exitCode=1;
}
if(require.main===module)main();
module.exports={createLibrary,exportRig};
