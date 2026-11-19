// Bounded offline replay of actual archived functions; no network or game UI.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const root=require('node:path').resolve(__dirname, '../..'),load=require(path.join(root,'smoke_vehicle_dynamics')).archivedModules();
const file=path.join(root,'local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js'),source=fs.readFileSync(file,'utf8');
function extract(marker){
 const markerAt=source.indexOf(marker);if(markerAt<0)throw Error('Missing exact archived marker:'+marker);
 const start=source.indexOf('function',markerAt),open=source.indexOf('{',start);let depth=0,quote=null,escape=false;
 for(let i=open;i<source.length;i++){
  const c=source[i];if(quote){if(escape)escape=false;else if(c==='\\')escape=true;else if(c===quote)quote=null;continue}
  if(c==='"'||c==="'"){quote=c;continue}if(c==='{')depth++;if(c==='}'&&!--depth)return{start,end:i+1,text:source.slice(start,i+1)};
 }
 throw Error('Unbalanced bounded function');
}
(async()=>{
 const R=load(55077);await R.init();const T=load(85339),materials=load(77287).aM;
 const controller=extract('em=function(e,t,l){let{hold:n,into:r}=e'),probe=extract('nL=function(e){let{RAPIER:t,world:l}=e');
 const evidenceDirectory=path.join(path.dirname(process.argv[3]),'evidence');fs.mkdirSync(evidenceDirectory,{recursive:true});
 fs.writeFileSync(path.join(evidenceDirectory,'archived-climb-functions.js'),'const archivedClimbController='+controller.text+';\nconst archivedClimbProbe='+probe.text+';\n');
 const constants={d:T,n5:[-.4,-1.1],n3:[-.4,0],n4:[.15,1],n6:[.5,0],n7:.25,re:{JUMP:20,HANG:21,PULL:22,EDGE:23,STAND:24,VAULT:25}};
 const create=vm.runInNewContext('('+controller.text+')',constants);
 const makeProbe=vm.runInNewContext('('+probe.text+')',{...constants,n0:{aM:materials},n2:new Set([17,18]),n1:[.15,.3,.45],
  n8:[[.6,1.75],[.6,1.3],[.6,.85],[.3,.65],[0,.5],[0,.1],[0,-.3]],n9:[[1.1,-.2],[1.1,.2],[1.1,.6],[.7,.6],[.35,.6],[0,.6]],rt:{x:0,y:0,z:0,w:1}});
 const vec=v=>new T.Pq0(...v),array=v=>[v.x,v.y,v.z],durations=JSON.parse(fs.readFileSync(process.argv[2]));
 const cases=[];
 for(const hz of[30,60,120])for(const kind of['low-stand','low-vault','high-hang-pull','high-direct-pull','hang-drop','edge-timeout','jump-timeout']){
  const high=!kind.startsWith('low')&&!kind.startsWith('edge'),vault=kind==='low-vault';
  const heading=hz===30?359*Math.PI/180:hz===60?-179*Math.PI/180:Math.PI;
  const inward=[-Math.sin(heading),0,-Math.cos(heading)],hold=[0,high?2.7:1.8,0];
  const initial=kind.endsWith('timeout')?[400,0,400]:[inward[0]*-.7,0,inward[2]*-.7];
  const ledge={hold:vec(hold),into:vec(inward),heading,high,vault},c=create(ledge,vec(initial),durations),frames=[];
  for(let i=0;i<hz*8;i++){
   const pull=kind==='high-direct-pull'||kind==='high-hang-pull'&&i>hz*2,drop=kind==='hang-drop'&&i>hz;
   const result=c.step(1/hz,pull,drop);frames.push({delta:1/hz,pull,drop,feet:array(c.feet),part:c.part,result:result??null});if(result)break;
  }
  cases.push({name:kind,hz,ledge:{hold,into:inward,heading,high,vault},initial,frames});
 }
 const probeCases=[];
 for(const scenario of[
  {name:'low-wall',top:1.8,depth:2},{name:'high-wall',top:2.7,depth:2},
  {name:'thin-fence',top:1.8,depth:.08},{name:'too-high',top:4.2,depth:2},
  {name:'barred17',top:1.8,depth:2,material:17},{name:'barred18',top:1.8,depth:2,material:18},
  {name:'slow-vehicle',top:1.8,depth:2,speed:.49},{name:'fast-vehicle',top:1.8,depth:2,speed:.51},
  {name:'exact-speed-boundary',top:1.8,depth:2,speed:.5},{name:'PED-ignored',top:1.8,depth:2,material:materials.PED},
  {name:'fixed-parent-wall',top:1.8,depth:2,parent:'fixed'},{name:'kinematic-parent-wall',top:1.8,depth:2,parent:'kinematic',speed:.1},
  {name:'PED-in-front-of-wall',top:1.8,depth:2,pedFront:true},{name:'fast-body-in-front-of-wall',top:1.8,depth:2,fastFront:true},
  {name:'ceiling-obstructed',top:1.8,depth:2,ceiling:true},{name:'body-clearance-obstructed',top:1.8,depth:2,bodyBlock:true},
  {name:'no-wall',top:0,depth:0},{name:'limited-reach',top:3.1,depth:2,extended:false}
 ]){
  const world=new R.World({x:0,y:-9.81,z:0}),map=new Map,queries=[];
  function box(x,y,z,hx,hy,hz,material=0,dynamic=false,speed=0,parent=null){
   const descBody=parent==='fixed'?R.RigidBodyDesc.fixed():parent==='kinematic'?R.RigidBodyDesc.kinematicVelocityBased():dynamic?R.RigidBodyDesc.dynamic():null;
   const body=descBody?world.createRigidBody(descBody.setTranslation(x,y,z).setLinvel(speed,0,0).setGravityScale(0)):undefined;
   const desc=R.ColliderDesc.cuboid(hx,hy,hz).setCollisionGroups(0x0087ffff);
   if(!body)desc.setTranslation(x,y,z);const c=world.createCollider(desc,body);map.set(c.handle,material);
  }
  if(scenario.depth)box(0,scenario.top/2,-.8-scenario.depth/2,1,scenario.top/2,scenario.depth/2,scenario.material??0,scenario.speed!==undefined,scenario.speed??0,scenario.parent);
  if(scenario.pedFront)box(0,1.6,-.4,.15,1.6,.1,materials.PED);
  if(scenario.fastFront)box(0,1.6,-.4,.15,1.6,.1,0,true,1);
  if(scenario.ceiling)box(0,2.6,0,1,.1,1);
  if(scenario.bodyBlock)box(0,2.8,-1.02,.1,.15,.1);
  // Browser's regular world has already stepped before its frame queries.
  world.step();
  function collider(c){const b=c.parent(),v=b?.linvel();return{fixed:!b||b.isFixed(),speed:v?Math.hypot(v.x,v.y,v.z):0,material:map.get(c.handle)??-1}}
  const cast=world.castRayAndGetNormal.bind(world),overlap=world.intersectionsWithShape.bind(world);
  world.castRayAndGetNormal=(ray,max,solid,flags,groups,a,b,predicate)=>{
   const hit=cast(ray,max,solid,flags,groups,a,b,predicate);
   queries.push({type:'ray',origin:array(ray.origin),direction:array(ray.dir),distance:max,groups,
    hit:hit?{distance:hit.timeOfImpact,normal:array(hit.normal),collider:collider(hit.collider)}:null});return hit;
  };
  world.intersectionsWithShape=(position,rotation,shape,callback,flags,groups,a,b,predicate)=>{
   const colliders=[];overlap(position,rotation,shape,c=>{colliders.push(collider(c));return callback(c)},flags,groups,a,b,predicate);
   queries.push({type:'sphere',origin:array(position),radius:shape.radius,groups,colliders});
  };
  const result=makeProbe({RAPIER:R,world,materials:map}).find(vec([0,0,0]),0,scenario.extended!==false);
  probeCases.push({name:scenario.name,scenario,feet:[0,0,0],heading:0,extended:scenario.extended!==false,queries,
   result:result?{hold:array(result.hold),into:array(result.into),heading:result.heading,high:result.high,vault:result.vault}:null});
  world.free();
 }
 const report={authority:'Actual archived browser functions in controlled synthetic worlds; NOT retail GTA SA behavior',
  source:{chunk:path.relative(root,file),sha256:crypto.createHash('sha256').update(source).digest('hex'),coordinateOffsets:'UTF-16 character offsets, half-open',
   functions:{controller:{start:controller.start,end:controller.end},probe:{start:probe.start,end:probe.end}},rapier:R.version(),pedMaterial:materials.PED},durations,cases,probeCases};
 fs.writeFileSync(process.argv[3],JSON.stringify(report));
 console.log('Archived climb source',report.source,'controllerframes',cases.reduce((a,c)=>a+c.frames.length,0),'probequeries',probeCases.reduce((a,c)=>a+c.queries.length,0));
})().catch(e=>{console.error(e.stack);process.exitCode=1});
