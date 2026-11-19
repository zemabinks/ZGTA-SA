// SPDX-License-Identifier: AGPL-3.0-only
// Portable authored vectors/planes only; never imports original game code/data.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),crypto=require('node:crypto');
const adapter=require('../../browser_remote_suspension'),{patch,prepare}=require('../../tools/assets/prepare_browser_remote_suspension');
let checks=0;const check=(value,label)=>{checks++;assert(value,label)},same=(a,b,label)=>{checks++;assert.deepEqual(a,b,label)};
class V{constructor(x=0,y=0,z=0){Object.assign(this,{x,y,z})}clone(){return new V(this.x,this.y,this.z)}}
class Ray{constructor(origin,direction){Object.assign(this,{origin,direction})}}
const group={position:new V(0,.001,0),scale:new V(1,1,1),quaternion:{x:0,y:0,z:0,w:1,clone(){return{...this}}},getWorldPosition(){return this.position.clone()},getWorldQuaternion(){return this.quaternion.clone()},getWorldScale(){return this.scale.clone()}};
const wheels=[[true,true],[false,true],[true,false],[false,false]].map(([front,left])=>({front,left,radius:.35,centre:new V(left?-.9:.9,.45,front?-1.6:1.6),home:new V(0,0,-.35),mesh:{position:new V(0,0,-.35),quaternion:{x:1,y:2,z:3,w:4}}}));
const built={kind:'car',table:{flags:0,upper:.25,lower:-.15},wheels};
const world={castRayAndGetNormal(ray,max,solid,flags,groups,exclude,body,predicate){
 const objects=[{height:.5,parent:()=>({isFixed:()=>false})},{height:0,parent:()=>null}];
 for(const object of objects){if(!predicate(object))continue;const distance=(object.height-ray.origin.y)/ray.direction.y;if(distance>=0&&distance<=max)return{timeOfImpact:distance,normal:new V(0,1,0)}}return null;
}};
const env={world,RAPIER:{Ray}},pose=JSON.stringify(group.position),turns=JSON.stringify(wheels.map(w=>w.mesh.quaternion));
check(adapter.apply(built,group,env),'Static authored contact unavailable');
for(const w of wheels){const bottom=group.position.y+w.centre.y+(w.mesh.position.z-w.home.z)-w.radius;check(Math.abs(bottom)<1e-12,'Tire sphere not tangent to authored plane')}
same(JSON.stringify(group.position),pose,'Body pose changed');same(JSON.stringify(wheels.map(w=>w.mesh.quaternion)),turns,'Spin/steer rotation changed');
const offsets=wheels.map(w=>w.mesh.position.z);
for(const fps of [15,30,60,120,144])for(let frame=0;frame<3;frame++){check(adapter.apply(built,group,env),'Repeated contact failed');same(wheels.map(w=>w.mesh.position.z),offsets,'Frame schedule '+fps+' changed contact')}
const partial={RAPIER:{Ray},world:{castRayAndGetNormal(ray,max){if(ray.origin.z>0)return null;return{timeOfImpact:ray.origin.y,normal:new V(0,1,0)}}}};
check(!adapter.apply(built,group,partial),'Partial contact set was published');same(wheels.map(w=>w.mesh.position.z),wheels.map(w=>w.home.z),'Partial contacts left a mixed stale pose');
check(adapter.apply(built,group,env),'Complete contact did not recover after missing coverage');
check(!adapter.apply(built,group,null),'Absent world treated as ready');same(wheels.map(w=>w.mesh.position.z),wheels.map(w=>w.home.z),'Missing world retained stale offset');
group.position.y=3;check(!adapter.apply(built,group,env),'Unknown browser miss invented a floor');group.position.y=.001;
built.hydraulics=true;wheels[0].mesh.position.z=123;check(!adapter.apply(built,group,env),'Hydraulic owner overwritten');same(wheels[0].mesh.position.z,123,'Hydraulic local changed');built.hydraulics=false;
for(const kind of ['bike','boat','train','plane','heli']){built.kind=kind;check(!adapter.apply(built,group,env),'Unsupported type '+kind)}built.kind='car';
check(!adapter.apply(built,group,{RAPIER:{Ray},world:{castRayAndGetNormal(){throw Error('Disposed')}}}),'Disposed engine escaped containment');
const synthetic='function authoredUpdate(){return ((0,fd.wl)(A.built,T.steer,0,0),42)}';
const hook=',globalThis.ZGTARemoteSuspension.apply(A.built,A.group,R)';
same(patch(synthetic).replace(hook,''),synthetic,'Guard patch changed the authored surrounding expression');
assert.throws(()=>patch('missing'));checks++;assert.throws(()=>patch(synthetic+synthetic));checks++;
const out=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/research/remote-suspension-108/portable-browser');fs.mkdirSync(out,{recursive:true});
const input=path.join(out,'authored-input-'+Date.now()+'.js');fs.writeFileSync(input,synthetic,{flag:'wx'});
const hash=crypto.createHash('sha256').update(synthetic).digest('hex'),output=path.join(out,'prepared-'+Date.now(),'authored.js');
assert.throws(()=>prepare({input,expectedSHA256:'0'.repeat(64),output}));checks++;
const prepared=prepare({input,expectedSHA256:hash,output});same(fs.readFileSync(input,'utf8'),synthetic,'Preparation mutated source');
assert.throws(()=>prepare({input,expectedSHA256:hash,output}));checks++;
const outside=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-suspension-authored-')),link=path.join(out,'escape-'+Date.now());fs.symlinkSync(outside,link,'dir');
try{assert.throws(()=>prepare({input,expectedSHA256:hash,output:path.join(link,'must-not-create','out.js')}));checks++;check(!fs.existsSync(path.join(outside,'must-not-create')),'Rejected parent created data outside ignored output')}finally{fs.unlinkSync(link);fs.rmSync(outside,{recursive:true,force:true})}
const report={status:'PASS',checks,scope:'Independent synthetic vectors/planes and authored patch fixture only; no original game code, data or browser execution',prepared};fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
