#!/usr/bin/env node
// Run original vehicle scene poses offline; retain source data locally only.
const fs=require('node:fs'),path=require('node:path');
const {createLibrary}=require('./prepare_native_vehicle_rigs');
function main(){
  const library=createLibrary(),{T}=library,selected=new Set([420,433,432,481,522,461,520,476,519,577,553,592,487,417,511,430,537]);
  const requested=process.argv.slice(2).map(Number);
  const cases=[];
  for(const definition of library.catalogue.Wd){
    if(requested.length&&!requested.includes(Number(definition.id)))continue;
    library.rig.clock.value=0;const built=library.build(definition.id),objects=[];
    built.root.userData.model.traverse(object=>objects.push(object));
    const metadata=JSON.parse(fs.readFileSync(path.join(library.game,'native/models',definition.model+'.rig.json'),'utf8'));
    if(objects.length!==metadata.nodes.length)throw Error('Rig node count mismatch '+definition.id);
    const count=selected.has(Number(definition.id))?120:1,frames=[];
    for(let i=0;i<count;i++){
      const input={steering:Math.sin(i*.07)*.65,rearSteering:Math.cos(i*.03)*.1,frontSpin:i*.31,rearSpin:i*.47,
        offsets:[0,1,2,3].map(w=>Math.sin(i*.1+w)*.07),drop:[Math.sin(i*.08)*.04,Math.cos(i*.05)*.04],lean:Math.sin(i*.03)*.6,crank:i*.013,
        rotor:.22,rotorSpin:i*.31,nozzle:2500+2500*Math.sin(i*.04),gearUp:i>=40&&i<100,
        looks:Array.from({length:11},(_,p)=>Math.floor(i/20+p)%3),tyres:[0,1,2,3].map(w=>(Math.floor(i/30)+w)%3),
        doorAngles:Array.from({length:6},(_,d)=>Math.sin(i*.03+d)*.9),doorAxes:[0,0,2,2,2,2],lights:i%2===0,braking:i%3===0,scorched:i>=100};
      library.rig.clock.value+=1000/60;
      const bike=built.motion.kind==='bike',front=bike?input.frontSpin*built.motion.hubs.front.radius/.36:input.frontSpin,rear=bike?input.rearSpin*built.motion.hubs.rear.radius/.36:input.rearSpin;
      library.load(62540).wl({...built.motion,table:built.table,wheels:built.wheels,flat:input.tyres,rearSteer:input.rearSteering},input.steering,front,rear,
        {lean:input.lean,drop:input.drop,crank:input.crank,rotor:input.rotor,spin:input.rotorSpin,gearUp:input.gearUp,nozzle:input.nozzle});
      for(let part=0;part<6;part++)built.damage.swing(part,input.doorAngles[part],input.doorAxes[part]);
      built.damage.show({looks:input.looks,lights:[0,0,0,0],wheels:input.tyres});
      for(const wheel of built.wheels){const index=2*!wheel.left+ +!wheel.front;wheel.mesh.position.z=wheel.home.z+input.offsets[index]}
      built.root.updateMatrixWorld(true);const inverse=built.root.matrixWorld.clone().invert();
      const matrices=objects.map(object=>[...inverse.clone().multiply(object.matrixWorld).elements]);
      const visible=objects.map(object=>object.visible);
      const samples=[];
      objects.forEach((object,node)=>{if(!object.isMesh||!object.geometry?.attributes?.position)return;const p=object.geometry.attributes.position;
        for(const index of [...new Set([0,Math.floor(p.count/2),p.count-1])]){
          const local=new T.Pq0().fromBufferAttribute(p,index),world=local.clone().applyMatrix4(inverse.clone().multiply(object.matrixWorld));
          samples.push({node,local:[local.x,local.y,local.z],world:[world.x,world.y,world.z]});
        }});
      frames.push({input,delta:1/60,matrices,visible,samples});
    }
    cases.push({id:Number(definition.id),model:definition.model,frames});library.geometry.xd(built.root,null);
    console.log(definition.id,definition.model,frames.length);
  }
  fs.writeFileSync(path.join(__dirname,'local-only/physics-fixtures/vehicle-rigs.json'),JSON.stringify({version:1,source:'Original88711 scene +62540.wl/rig +39851 damage transforms',cases}),{mode:0o600});
  console.log('PASS original complete vehicle rig references saved locally');
}
if(require.main===module)main();
