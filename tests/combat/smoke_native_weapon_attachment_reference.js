// Execute actual offline Ko/R6 with the real rig and equipment. Original
// bundles, meshes and generated vertex measurements remain in local-only/.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {archivedModules}=require('../vehicles/smoke_vehicle_dynamics');
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 g.fetch=async url=>{const file=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site',String(url).split('?')[0]);if(!fs.existsSync(file))return{ok:false};const b=fs.readFileSync(file);return{ok:true,json:async()=>JSON.parse(b),arrayBuffer:async()=>{const a=new Bytes(b.length);a.set(b);return a.buffer}}};
 g.setTimeout=(f,t)=>{const timer=setTimeout(f,t);timer.unref();return timer};g.clearTimeout=clearTimeout;
 const T=load(85339),api=load(49368),weapons=load(60662),main=load.factories[19737].toString();
 const selectionBegin=main.indexOf('t8=()=>'),selectionEnd=main.indexOf(',t9=',selectionBegin);
 assert(selectionBegin>=0&&selectionEnd>selectionBegin,'Effective-selection source boundary changed');
 const selection=main.slice(selectionBegin+3,selectionEnd),td={on:false},tf={flying:false},tx={weapon:46};
 const selected=factory.constructor('td','tf','tx','F','return ('+selection+')')(td,tf,tx,weapons);
 const visibility=[];
 for(const item of weapons.Mc)for(const swim of[false,true])for(const flying of[false,true]){
  td.on=swim;tf.flying=flying;tx.weapon=item.id;
  visibility.push({weapon:item.id,swimming:swim,flying,arm:item.flags.arm===true,expected:selected()});
 }
 const invBegin=main.indexOf('tx=function(){'),invEnd=main.indexOf('(),tv=',invBegin);
 assert(invBegin>=0&&invEnd>invBegin,'Inventory source boundary changed');
 const inventory=factory.constructor('F','return ('+main.slice(invBegin+3,invEnd)+')()')(weapons);
 inventory.give(22,80);assert.equal(inventory.weapon,22);inventory.give(46,1);assert.equal(inventory.weapon,46);
 inventory.take(22);assert.equal(inventory.weapon,22);inventory.drop(46);assert.equal(inventory.weapon,22);
 inventory.give(46,1);inventory.drop(46);assert.equal(inventory.weapon,0);
 const ped=await api.gp('bmori','bmori'),data=await api.av(),style=await load(66799).r({model:'bmori'},data),animator=api.R6(ped,style,data.clips),holder=weapons.Ko();
 for(const fly of[{state:1},{state:11},null]){animator.update(0,{fly});for(let i=0;i<40;i++)await Promise.resolve()}
 const settle=async()=>{for(let i=0;i<20;i++)await new Promise(setImmediate)};
 holder.hold(ped,46);await settle();assert.equal(holder.guns.length,1);
 const bag=holder.guns[0];assert.equal(bag.parent,ped.bones.get(api.LS.SPINE1));assert.deepEqual(Array.from(bag.position.toArray()),[.1,-.15,0]);assert.equal(bag.rotation.y,Math.PI/2);
 assert(bag.rotation.x===0&&bag.rotation.z===0);assert.deepEqual(Array.from(bag.scale.toArray()),[1,1,1]);
 const native=fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/models/gun_para.bin')),count=native.readUInt32LE(4),samples=[];
 bag.updateWorldMatrix(true,true);let mesh;bag.traverse(o=>{if(o.isMesh)mesh=o});assert(mesh);const inv=bag.matrixWorld.clone().invert();
 for(let index=0;index<count;index+=Math.max(1,Math.floor(count/12))){const point=[0,1,2].map(axis=>native.readFloatLE(16+index*12+axis*4));let found=-1;
  for(let source=0;source<mesh.geometry.attributes.position.count;source++){const p=new T.Pq0().fromBufferAttribute(mesh.geometry.attributes.position,source).applyMatrix4(inv.clone().multiply(mesh.matrixWorld));if(Math.hypot(...point.map((v,a)=>v-[p.x,p.y,p.z][a]))<0.000001){found=source;break}}
  assert(found>=0,'Baked native vertex must match actual DFF basis');samples.push({index,source:found,point});
 }
 const rows=[];let weapon=-1;
 for(let frame=0;frame<480;frame++){
  const state=frame<120?0:frame<315?1+Math.floor((frame-120)/15):0,chosen=frame<65?46:frame<100?22:frame<350?46:frame<365?0:46;
  td.on=frame>=365&&frame<385;tf.flying=state===12||state===13;tx.weapon=chosen;
  const held=selected();if(held!==weapon){weapon=held;holder.hold(ped,weapon);animator.arm(await weapons.OP(weapon));await settle()}
  const input={ratio:frame<100?.8:0,look:Math.sin(frame*.029)*.4,fly:state?{state,pitch:Math.sin(frame*.017)*.6,roll:Math.cos(frame*.019)*.4}:null};
  const method=frame===400?'die':frame===445?'revive':null;
  if(method==='die')animator.die('koFront');if(method==='revive')animator.revive();
  const delta=[1/60,1/50,1/75][frame%3];animator.update(delta,input);
  const feet=[1500+frame*.013,-1740+frame*.007,13.4],heading=Math.sin(frame*.011)*1.8;
  ped.group.position.set(feet[0],feet[2],-feet[1]);ped.group.rotation.y=-heading;ped.group.updateMatrixWorld(true);
  const row={frame,chosen,weapon,state,swimming:td.on,input,method,dead:animator.dead,delta,feet,heading,vertices:[],guns:holder.guns.length};
  if(weapon===46){const model=holder.guns[0];assert.equal(model.parent,ped.bones.get(3));let object;model.traverse(o=>{if(o.isMesh)object=o});
   row.vertices=samples.map(({index,source,point})=>{const p=new T.Pq0().fromBufferAttribute(object.geometry.attributes.position,source).applyMatrix4(object.matrixWorld);return{index,point,world:[p.x,-p.z,p.y]}});
  }
  rows.push(row);
 }
 // Async selection invalidation and actual missing-bone fallback semantics.
 holder.hold(ped,0);holder.hold(ped,46);holder.hold(ped,0);await settle();assert.equal(holder.guns.length,0);
 const spine=ped.bones.get(3);ped.bones.delete(3);holder.hold(ped,46);await settle();
 assert.equal(holder.guns[0].parent,ped.bones.get(24));assert.deepEqual(Array.from(holder.guns[0].position.toArray()),[0,0,0]);assert(holder.guns[0].rotation.y===0);
 holder.hold(ped,0);ped.bones.set(3,spine);const hand=ped.bones.get(24);ped.bones.delete(24);holder.hold(ped,46);await settle();assert.equal(holder.guns.length,0);ped.bones.set(24,hand);
 holder.dispose();ped.dispose();
 fs.writeFileSync(process.argv[2],JSON.stringify({authority:'Actual archived60662.Ko +49368.R6 +19737 inventory/effective selection; not retail executable behavior',rows,visibility,samples: samples.length,inventoryChecks:6,holderTransitions:5}));
 console.log('Actual Ko/R6 attachment reference:',rows.length,'real rig frames,',visibility.length,'effective selections,',samples.length,'real mesh points');
})().catch(error=>{console.error(error.stack);process.exitCode=1});
