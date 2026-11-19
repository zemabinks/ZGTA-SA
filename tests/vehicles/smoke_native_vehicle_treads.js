#!/usr/bin/env node
'use strict';
// Owner-local original support-buffer posing and ray equations. Only an
// additional export exposes the unchanged private ray function.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {createLibrary}=require('../../tools/assets/prepare_native_vehicle_rigs');
const lib=createLibrary(),load=lib.load,T=lib.T,source=load.factories[58683].toString(),moduleBox={exports:{}};
assert(source.includes('MC:()=>I'),'Archived support query export boundary changed');
Function('return ('+source.replace('MC:()=>I','_query:()=>_,MC:()=>I')+')')()(moduleBox,moduleBox.exports,load);
const query=moduleBox.exports._query,models=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/vehicles.physics.json'))).models;
const original=load.factories[19737].toString(),start=original.indexOf('function vh(e,t){'),end=original.indexOf('var vm=l(39851)',start);
assert(start>=0&&end>start);const vh=original.slice(start,end),identity=new T.kn4();
const rotations=[[0,0,0],[.3,.8,-.2],[-.4,-2.7,.35],[0,Math.PI,0],[.8,1.2,.6]].map(([x,y,z])=>{
 const q=new T.PTz().setFromEuler(new T.O9p(x,y,z,'YXZ'));return {x:Math.fround(q.x),y:Math.fround(q.y),z:Math.fround(q.z),w:Math.fround(q.w)};
});
function rays(tread,grid,poses){
 const samples=[],position={x:20,y:.7,z:-12};
 for(const rotation of rotations.slice(0,poses)){
  const q=new T.PTz(rotation.x,rotation.y,rotation.z,rotation.w),vertices=[];
  for(let i=0;i<tread.positions.length;i+=3)vertices.push(new T.Pq0(tread.positions[i],tread.positions[i+1],tread.positions[i+2]).applyQuaternion(q).add(position));
  const minX=Math.min(...vertices.map(v=>v.x))-.3,maxX=Math.max(...vertices.map(v=>v.x))+.3;
  const minZ=Math.min(...vertices.map(v=>v.z))-.3,maxZ=Math.max(...vertices.map(v=>v.z))+.3,top=Math.max(...vertices.map(v=>v.y))+1;
  const body={userData:{tread},translation:()=>position,rotation:()=>rotation};
  for(let x=0;x<grid;x++)for(let z=0;z<grid;z++){
   const origin={x:minX+(maxX-minX)*x/(grid-1),y:top,z:minZ+(maxZ-minZ)*z/(grid-1)},distance=100;
   samples.push({position:Object.values(position),rotation:[rotation.x,rotation.y,rotation.z,rotation.w],origin:Object.values(origin),distance,hit:query(body,origin,distance)});
  }
 }
 return samples;
}
const base=[];
for(const row of Object.values(models)){
 const bytes=fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game',row.model+'.dff')),collision=load(78315).A(bytes).collision,built={collision,origin:row.origin};
 const tread=load(58683).E4(built);if(!tread)continue;
 base.push({id:row.id,positions:[...tread.positions],indices:[...tread.indices],rays:rays(tread,3,5)});
}
const working=[];
for(const id of [406,443,486,525,530,592]){
 const built=lib.build(id);built.origin=models[id].origin;built.collision=built.parsed.collision;
 const profile=built.coupling.configuration(built),apply=Function('d','vn','vd','vo','vl','let vi=new d.Pq0,vs=new d.Pq0,vc=new d.kn4,vu=new d.kn4;return ('+vh+');')(T,{[id]:profile.working},v=>T.cj9.clamp(v,0,2500),(e,_spec,v)=>built.coupling.pose(e,v),load(58683));
 const frames=[];
 for(let work=0;work<=2500;work+=50){
  apply(built,work);const tread=load(58683).E4(built);
  frames.push({work,matrix:[...(built.workMatrix??identity).elements],positions:[...tread.positions],rays:rays(tread,5,3)});
 }
 working.push({id,frames});lib.geometry.xd(built.root,null);
}
const sha=s=>crypto.createHash('sha256').update(s).digest('hex');
fs.writeFileSync(process.argv[2],JSON.stringify({sourceSHA256:sha(source),workingSourceSHA256:sha(vh),base,working}),{mode:0o600});
console.log('Recorded',base.length,'actual support meshes,',working.length*51,'working poses and',base.reduce((n,r)=>n+r.rays.length,0)+working.reduce((n,r)=>n+r.frames.reduce((m,f)=>m+f.rays.length,0),0),'original support rays');
