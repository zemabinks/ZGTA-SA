#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require('./smoke_vehicle_dynamics');
async function main(){
  const load=archivedModules(),R=load(55077);await R.init();const T=load(85339),source=load.factories[62540].toString();
  const start=source.indexOf('tt=function(e,t){')+3,end=source.indexOf('},tl=',start)+1;
  if(start<3||end<=start)throw Error('Original62540 blast closure signature changed');
  const make=Function('n','Z','d','c','eI','el','e6','return ('+source.slice(start,end)+')');
  const models=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/vehicles.physics.json'))).models,cases=[];
  const vector=v=>[v.x,v.y,v.z],quaternion=q=>[q.x,q.y,q.z,q.w],f=Math.fround;
  for(const model of [420,432,446,481,522,520,487,476,537,449,515,457])for(let i=0;i<40;i++){
    const definition=models[model],world=new R.World({x:0,y:0,z:0}),p={x:f(1500.1+i*.23),y:f(15.3+i*.02),z:f(1730.7-i*.31)};
    const rotation=new T.PTz().setFromAxisAngle(new T.Pq0(0,1,0),-i*.021)
      .multiply(new T.PTz().setFromAxisAngle(new T.Pq0(1,0,0),i*.013))
      .multiply(new T.PTz().setFromAxisAngle(new T.Pq0(0,0,1),i*.009));
    const q={x:f(rotation.x),y:f(rotation.y),z:f(rotation.z),w:f(rotation.w)};
    const body=world.createRigidBody(R.RigidBodyDesc.dynamic().setGravityScale(0).setTranslation(p.x,p.y,p.z).setRotation(q));
    body.setLinvel({x:.12*i,y:-.03*i,z:.05*i},true);body.setAngvel({x:.013*i,y:-.009*i,z:.017*i},true);
    const before={position:vector(body.translation()),rotation:quaternion(body.rotation()),linearVelocity:vector(body.linvel()),angularVelocity:vector(body.angvel())};
    const distance=(i%10)*1.1,centre=new T.Pq0(f(p.x+Math.sin(i)*distance),f(p.y+Math.cos(i*.7)*distance),f(p.z+Math.cos(i)*distance));
    const turn=new T.PTz(...before.rotation),right=new T.Pq0(1,0,0).applyQuaternion(turn),forward=new T.Pq0(0,0,-1).applyQuaternion(turn),up=new T.Pq0(0,1,0).applyQuaternion(turn);
    let health=1000,damage=0;
    const wear={inflict(value){damage=value;health=Math.max(0,health-value)}};
    const context=()=>({position:new T.Pq0(...before.position).addScaledVector(up,definition.origin),right,forward,up,move:new T.Pq0(...before.linearVelocity).divideScalar(50),turn:new T.Pq0(...before.angularVelocity).divideScalar(50)});
    const blast=make(T,load(66242),definition,{rigid:body},wear,turn,context);blast(centre,false,model===432?.3:1);
    cases.push({model,before,centreGTA:[centre.x,-centre.z,centre.y],health,damage,angularVelocity:vector(body.angvel())});world.free();
  }
  fs.writeFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/physics-fixtures/vehicle-blast-manager.json'),JSON.stringify({version:1,source:'Actual62540.tt closure + original66242.xM + originalRapier Float setter',cases}),{mode:0o600});
  console.log('PASS',cases.length,'original vehicle blast-wrapper references saved locally');
}
main().catch(error=>{console.error(error);process.exitCode=1});
