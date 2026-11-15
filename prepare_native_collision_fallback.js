#!/usr/bin/env node
// Reconstructs a missing collision asset using the archived client's actual
// WRL2 loader, spatial ranges and render-mesh collision fallback. Game files
// and generated measurements remain under ignored local-only/.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {spawnSync}=require('node:child_process');
const {archivedModules}=require('./smoke_vehicle_dynamics');
const root=__dirname,worldDirectory=path.join(root,'local-only/site/game/world');
const digest=data=>crypto.createHash('sha256').update(data).digest('hex');
function declaration(source,name){
  const match=new RegExp('(?:async )?function\\*?\\s*'+name+'\\(').exec(source);
  if(!match)throw Error('Archived declaration missing: '+name);
  const start=match.index,brace=source.indexOf('{',start);let depth=0,quote=null,escape=false;
  for(let i=brace;i<source.length;i++){
    const c=source[i];if(quote){if(escape){escape=false;continue;}if(c==='\\'){escape=true;continue;}if(c===quote)quote=null;continue;}
    if(c==='"'||c==="'"||c==='`'){quote=c;continue;}
    if(c==='{')depth++;if(c==='}'&&!--depth)return source.slice(start,i+1);
  }throw Error('Unterminated archived declaration: '+name);
}
async function reconstruct(cell='i148'){
  if(!/^i\d+$/.test(cell))throw Error('Expected a named interior cell');
  const index=JSON.parse(fs.readFileSync(path.join(worldDirectory,'index.json'))),number=Number(cell.slice(1));
  const row=index.inside.cells.find(value=>value.cell===number);if(!row)throw Error('Unknown archived cell');
  const input=fs.readFileSync(path.join(worldDirectory,cell+'.bin'));
  const indexCount=input.readUInt32LE(8),layers=input.readUInt32LE(12);
  // The one missing public collision cell is fully opaque. This proves its
  // original alpha-sampling holed flags are all false at every image scale.
  // Other cells with transparency need the original texture sampler first.
  const texture=path.join(worldDirectory,cell+'.webp');
  const probe=spawnSync('python3',['-c',
    'from PIL import Image; import json,sys; im=Image.open(sys.argv[1]).convert("RGBA"); print(json.dumps({"size":im.size,"alpha":im.getextrema()[3]}))',texture],{encoding:'utf8'});
  if(probe.status!==0)throw Error(probe.stderr.trim());const image=JSON.parse(probe.stdout);
  if(image.alpha[0]!==255||Math.min(row.blend??indexCount,indexCount)!==indexCount)
    throw Error('This generator requires source-proven fully opaque/full-range geometry');
  const load=archivedModules(),three=load(85339),factory=load.factories[57153].toString();
  const parserSource=declaration(factory,'W'),rangeSource=declaration(factory,'F');
  const collisionSource=declaration(load.factories[39943].toString(),'f');
  const parser=Function('a','fetch','return ('+parserSource+');')(three,async()=>({ok:true,
    arrayBuffer:async()=>input.buffer.slice(input.byteOffset,input.byteOffset+input.byteLength)}));
  const split=Function('a','T','k','return ('+rangeSource+');')(three,3,8191);
  const collide=Function('n','return ('+collisionSource+');')(three);
  const geometry=await parser(cell),holed=new Uint8Array(layers);
  const meshes=await split(geometry,holed,indexCount,{opaque:null,solid:null,clear:null},3);
  const parts=meshes.map(mesh=>({range:mesh.userData.range,
    collision:collide(geometry,holed,...mesh.userData.range)})).filter(part=>part.collision.indices.length);
  let vertexCount=0,triangles=0;for(const part of parts){vertexCount+=part.collision.positions.length/3;triangles+=part.collision.indices.length/3;}
  const surfaceBytes=Math.ceil(triangles/4)*4;
  const output=Buffer.alloc(16+vertexCount*12+triangles*12+surfaceBytes);
  [0x324c4353,vertexCount,triangles,0].forEach((value,n)=>output.writeUInt32LE(value,n*4));
  let vertexBase=0,indexBase=0;const ranges=[];
  for(const part of parts){
    const {positions,indices}=part.collision;
    for(let n=0;n<positions.length;n+=3){const at=16+vertexBase*12+n*4;
      output.writeFloatLE(positions[n],at);output.writeFloatLE(-positions[n+2],at+4);output.writeFloatLE(positions[n+1],at+8);}
    for(let n=0;n<indices.length;n++)output.writeUInt32LE(indices[n]+vertexBase,16+vertexCount*12+(indexBase+n)*4);
    ranges.push({indexStart:indexBase,indexCount:indices.length,sourceRange:part.range});
    vertexBase+=positions.length/3;indexBase+=indices.length;
  }
  output.fill(2,16+vertexCount*12+triangles*12); // Original fallback O() defaults: surface2/material-1.
  const R=load(55077);await R.init();const world=new R.World({x:0,y:-18,z:0});
  const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
  for(const part of parts){const p=part.collision.positions;world.createCollider(R.ColliderDesc.trimesh(p,part.collision.indices).setFriction(0.8).setCollisionGroups(131071));
    for(let n=0;n<p.length;n+=3)for(let axis=0;axis<3;axis++){min[axis]=Math.min(min[axis],p[n+axis]);max[axis]=Math.max(max[axis],p[n+axis]);}}
  world.step();const rays=[],distance=max[1]-min[1]+4;
  for(let x=0;x<9;x++)for(let z=0;z<9;z++){
    const origin=[min[0]+(max[0]-min[0])*(x+0.5)/9,max[1]+2,min[2]+(max[2]-min[2])*(z+0.5)/9];
    const hit=world.castRayAndGetNormal(new R.Ray({x:origin[0],y:origin[1],z:origin[2]},{x:0,y:-1,z:0}),distance,true);
    rays.push({origin,direction:[0,-1,0],distance,hit:hit?{distance:hit.timeOfImpact,normal:[hit.normal.x,hit.normal.y,hit.normal.z]}:null});
  }
  world.free();if(!rays.some(ray=>ray.hit))throw Error('Original fallback returned no floor hits');
  const manifest={version:1,cell,reconstructed:true,publisherCollisionAssetAvailable:false,
    source:'Original39943.addCell render-mesh fallback; parser57153.W, ranges57153.F, collision39943.f',
    archiveVersion:index.version,inputSHA256:digest(input),textureSHA256:digest(fs.readFileSync(texture)),textureProof:image,
    functions:{parserSHA256:digest(parserSource),rangesSHA256:digest(rangeSource),collisionSHA256:digest(collisionSource)},
    outputSHA256:digest(output),vertices:vertexCount,triangles,parts:ranges,rapierBounds:{min,max},rays};
  const outputPath=path.join(worldDirectory,cell+'.col.bin'),manifestPath=path.join(worldDirectory,cell+'.col.generated.json');
  if(fs.existsSync(outputPath)&&!fs.existsSync(manifestPath))throw Error('Refusing to replace an existing non-generated collision asset');
  fs.writeFileSync(outputPath,output,{mode:0o600});fs.writeFileSync(manifestPath,JSON.stringify(manifest),{mode:0o600});
  console.log(JSON.stringify({cell,reconstructed:true,vertices:vertexCount,triangles,parts:ranges.length,originalRayHits:rays.filter(ray=>ray.hit).length,outputSHA256:manifest.outputSHA256}));
  return manifest;
}
if(require.main===module)reconstruct(process.argv[2]??'i148').catch(error=>{console.error(error.message);process.exitCode=1});
module.exports={reconstruct};
