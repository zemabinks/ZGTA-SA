// Execute the actual archived weapon holder, real DFF rig and R6 animations.
// Original bundles/assets and output measurements stay in ignored local-only.
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require('./smoke_vehicle_dynamics');
(async()=>{
 const cases=[];
 for(const spec of[{id:22},{id:22,skill:2},{id:25},{id:25,skill:0},{id:37},{id:41}]){
  const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
  g.fetch=async url=>{const file=path.join(__dirname,'local-only/site',String(url).split('?')[0]);if(!fs.existsSync(file))return{ok:false};const b=fs.readFileSync(file);return{ok:true,json:async()=>JSON.parse(b),arrayBuffer:async()=>{const a=new Bytes(b.length);a.set(b);return a.buffer}}};
  g.setTimeout=(f,t)=>{const timer=setTimeout(f,t);timer.unref();return timer};g.clearTimeout=clearTimeout;
  const table=load(27436).gc,base=table[spec.id];if(spec.skill!==undefined)table[spec.id]=[base,...base.levels??[]].find(v=>v.skill===spec.skill);
  const T=load(85339),api=load(49368),weapons=load(60662),ped=await api.gp('bmori','bmori'),data=await api.av(),style=await load(66799).r({model:'bmori'},data),animator=api.R6(ped,style,data.clips),holder=weapons.Ko();
  let weapon=spec.id,definition=await weapons.OP(weapon);animator.arm(definition);holder.hold(ped,weapon);
  for(let i=0;i<20;i++)await new Promise(setImmediate);
  if(!holder.guns.length)throw Error('Actual weapon model failed to attach');
  function profile(value,id){const row=weapons.U1(id),out={...value,flags:row.flags,use:row.use,aims:row.aims};out.clips=Object.fromEntries(Object.entries(value.clips??{}).map(([key,clip])=>[key,clip?row.block+'/'+clip.name.toLowerCase():null]));if(!Number.isFinite(out.breakout))delete out.breakout;return out}
  let activeProfile=profile(definition,weapon);const rows=[];
  for(let frame=0;frame<100;frame++){
   let change=null;
   if(frame===78&&spec.id===22&&spec.skill===undefined){weapon=23;definition=await weapons.OP(weapon);animator.arm(definition);holder.hold(ped,weapon);for(let i=0;i<20;i++)await new Promise(setImmediate);activeProfile=profile(definition,weapon);change=activeProfile}
   if(frame===67)animator.reload();
   const control={aim:true,held:true,fire:frame>=22&&frame<63,ready:true},input={ratio:frame<40?.6:0,crouch:frame>=40&&frame<58,gun:{pitch:.3*Math.sin(frame*.05),yaw:.2*Math.cos(frame*.04)}};
   animator.control(control);animator.update(1/60,input);
   const feet=[1480+frame*.01,-1738+frame*.005,13],heading=.7+frame*.003;
   ped.group.position.set(feet[0],feet[2],-feet[1]);ped.group.rotation.y=-heading;ped.group.updateMatrixWorld(true);
   const right=new T.Pq0,left=new T.Pq0;holder.muzzle(right,false);holder.muzzle(left,true);
   rows.push({frame,weapon,skill:table[weapon].skill,feet,heading,input,control,change,profile:frame===0?activeProfile:null,
    right:[right.x,-right.z,right.y],left:[left.x,-left.z,left.y],shot:animator.shot,shotLeft:animator.shotLeft,reloading:animator.reloading,
    guns:holder.guns.length,rightHand:Array.from(ped.bones.get(api.LS.R_HAND).matrixWorld.elements),leftHand:Array.from(ped.bones.get(api.LS.L_HAND).matrixWorld.elements)});
  }
  cases.push({weapon:spec.id,skill:table[spec.id].skill,rows});holder.dispose();ped.dispose();
 }
 fs.writeFileSync(process.argv[2],JSON.stringify({authority:'Actual archived60662.Ko +49368.R6, real bmori DFF/ANP3; not retail runtime',cases}));
 console.log('Actual weapon-holder reference:',cases.length,'skill/weapon scenarios',cases.reduce((a,c)=>a+c.rows.length,0),'real rig frames');
})().catch(e=>{console.error(e.stack);process.exitCode=1});
