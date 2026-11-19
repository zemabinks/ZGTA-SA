// Execute bounded shipped input/fire expressions and real R6/ANP3 offline.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),{archivedModules}=require('../vehicles/smoke_vehicle_dynamics');
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 g.fetch=async url=>{const p=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site',String(url).split('?')[0]);if(!fs.existsSync(p))return{ok:false};const b=fs.readFileSync(p);return{ok:true,json:async()=>JSON.parse(b),arrayBuffer:async()=>{const a=new Bytes(b.length);a.set(b);return a.buffer}}};
 g.setTimeout=(f,t)=>{const v=setTimeout(f,t);v.unref();return v};g.clearTimeout=clearTimeout;
 const api=load(49368),F=load(60662),data=await api.av(),directory=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/_next/static/chunks');
 const source=fs.readFileSync(path.join(directory,fs.readdirSync(directory).find(n=>n.startsWith('9737.'))),'utf8');
 const begin=source.indexOf('let tn="melee"===eU&&9!==eB.id;'),end=source.indexOf(',(eS=',begin),input=source.slice(begin,end)+';';
 const a=source.indexOf('let tC="melee"===eU&&eL&&C&&T&&!C.firing?'),b=source.indexOf('if(!e0&&eL',a),c=source.indexOf(',(null==C?void 0:C.shot)',b);
 if(begin<0||end<0||a<0||b<0||c<0)throw Error('Original melee boundaries changed');
 const fire=source.slice(a,b)+source.slice(b+3,c)+';';
 const cases=[];
 for(const hz of [30,60,120])for(const spec of[{id:0,mode:'tap'},{id:0,mode:'held'},{id:0,mode:'guard'},{id:0,mode:'run'},{id:0,mode:'ground'},{id:5,mode:'tap'},{id:8,mode:'tap'},{id:9,mode:'held'}]){
  const ped=await api.gp('bmori','bmori'),style=await load(66799).r({model:'bmori'},data),C=api.R6(ped,style,data.clips);C.arm(await F.OP(spec.id));
  let accepted=false;const context={C,T:ped,eB:F.U1(spec.id),eU:'melee',tH:0,tU:false,e0:false,eG:false,tk:0,tx:{ready:true},th:true,S:{swing(){accepted=true}},lt:()=>context.groundTarget};vm.createContext(context);const rows=[];
  for(let i=0;i<hz*3;i++){
   const held=spec.mode==='held' ? true:spec.mode==='guard' ? i>=hz&&i<hz+2:i%Math.round(hz*.35)===0;
   const row={delta:Math.fround(1/hz),held,guard:spec.mode==='guard'&&i<hz,block:spec.mode==='guard'&&i>=hz/3&&i<hz*2/3,ratio:spec.mode==='run'?1.5:0,ground:spec.mode==='ground',weapon:spec.id};
   Object.assign(context,{l:row.delta,ew:held,ef:row.guard,eM:row.block,eH:true,V:row.ratio,K:row.ratio,groundTarget:row.ground});accepted=false;
   vm.runInContext('(function(){'+input+'tU=ew;'+fire+'})()',context);
   C.update(row.delta,{ratio:row.ratio,guard:context.ex,block:context.eb});
   rows.push({...row,accepted,shot:C.shot,swing:C.swing,aside:C.aside??null,guarding:context.ex,blocking:context.eb});
  }
  cases.push({...spec,hz,rows});ped.dispose();
 }
 const T=load(85339),ga=source.indexOf('lt=e=>{var t,l;let n=T.group.position,r=.75+e.ground.blow.radius'),gb=source.indexOf('},ll=null',ga);
 if(ga<0||gb<0)throw Error('Original ground selector boundary changed');
 const selector={d:{cj9:T.cj9},T:{group:{position:new T.Pq0()}},al:Math.PI/3,W:0,h:()=>selector.living,m:()=>selector.dead};vm.createContext(selector);
 vm.runInContext('var lt='+source.slice(ga+3,gb+1),selector);
 const geometry=[],three=a=>new T.Pq0(a[0],a[2],-a[1]);
 for(const heading of [0,Math.PI/2,Math.PI-.0001,-Math.PI+.0001])for(const targetHeading of [0,Math.PI/2])for(const x of [-1.6,-1.2,-.8,0,.8,1.2,1.6])for(const y of [-1.2,0,.8,1.2])for(const z of [-1.5,0,1.5]){
  const candidate={id:'target',feet:[x,y,z].map(Math.fround),heading:Math.fround(targetHeading),down:true,dead:false};
  selector.W=-Math.fround(heading);selector.living=[{id:candidate.id,position:three(candidate.feet),heading:-candidate.heading,down:true}];selector.dead=[];
  selector.e=F.U1(0);const selected=vm.runInContext('lt(e)',selector);
  geometry.push({heading:Math.fround(heading),candidate,expected:selected?.id??null});
 }
 fs.writeFileSync(process.argv[2],JSON.stringify({authority:'Actual main9737 input/fire/ground expressions + real49368.R6; not retail execution',cases,geometry}));
 console.log('Original melee reference',cases.length,'cases',cases.reduce((n,c)=>n+c.rows.length,0),'frames');
})().catch(e=>{console.error(e.stack);process.exitCode=1});
