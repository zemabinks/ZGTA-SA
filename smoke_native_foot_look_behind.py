#!/usr/bin/env python3
"""Replay the bounded archived render-time foot look-behind wrapper.

The official manual establishes the control, not its camera equations. These
equations are compared with the shipped browser wrapper, not a retail runtime.
All extracted bytes and generated measurements stay in ignored local-only.
"""
from pathlib import Path
import hashlib,json,os,subprocess,tempfile
from smoke_native_camera import JS as CAMERA_REFERENCE
ROOT=Path(__file__).resolve().parent
REPLAY=r'''
const wrapperStart=source.indexOf('let lN=!iP()'),wrapperEnd=source.indexOf('let lP=',wrapperStart),wrapper=source.slice(wrapperStart,wrapperEnd);
if(wrapperStart<0||wrapperEnd<0||wrapper.length>1500)throw Error('Archived foot wrapper boundary changed');
const cases=[];
for(const hz of [30,60,120])for(const initial of [-Math.PI-.003,Math.PI-.003,0,2*Math.PI-.003])for(const mode of ['normal','crouch','aim','scope','scope-unheld','ledge','parachute']){
 const {context,camera}=setup();let previousSight=null;const rows=[];
 const rear={o4:{position:new V(),quaternion:{copy(){}}},o6:new V(),ia:new V(),l_:true,nq:false,lT:false,lA:true,ub:{on:false}};
 camera.quaternion={copy(){}};camera.lookAt=v=>camera.target=v.clone();
 vm.createContext(rear);
 for(let i=0;i<24;i++){
  const aiming=(mode==='aim'||mode==='scope')&&i>=8&&i<13,sight=(mode==='scope'||mode==='scope-unheld')&&i>=8&&i<13?'scope':null;
  const input={position:[f32(1480+Math.sin(i*.08)*.3),f32(-1738+i*.035),f32(13+Math.sin(i*.13)*.1)],heading:f32(initial+i*.001),pitch:f32(-.1+Math.sin(i*.2)*.2),actorHeading:f32(-1.2),weapon:sight?34:22,
   aiming,crouching:mode==='crouch'&&i>=4&&i<20,holdingLedge:mode==='ledge'&&i>=10&&i<14,parachuting:mode==='parachute'&&i>=4&&i<20,sight,zoom:mode==='parachute'?3:2,delta:i===0?0:f32(1/hz),look:i>=6&&i<17?'behind':null,block:i>=14&&i<17?1:0};
  context.input=input;context.tx.weapon=input.weapon;context.tf.chuting=input.parachuting;context.em=input.holdingLedge?{}:null;context.W=-input.actorHeading;context.eE=input.crouching;context.tR=input.aiming&&!input.sight;context.tC=input.zoom;
  if(sight!==previousSight){context.tL=sight;if(sight){context.tF[sight]=context.tI[sight]=meta.footSights[sight].first;context.tq=context.tD=0}previousSight=sight}
  const collisions=[];
  const trace=(o,d,m)=>{collisions.push({origin:native(o),direction:native(d),distance:m});return hit(native(o),native(d),m,input.block)};
  context.camera=camera;context.position=three(input.position);context.clear=trace;
  vm.runInContext('original.follow(camera,position,clear,input.delta)',context);
  const normal=camera.position.clone(),direction=camera.getWorldDirection(new V()),normalTarget=normal.clone().addScaledVector(direction,10);
  camera.target=normalTarget.clone();Object.assign(rear,{tN:camera,pl:three(input.position),iP:()=>input.look==='behind',iz:()=>aiming,nw:{along:trace}});
  const active=vm.runInContext('(function(){'+wrapper+';return !!lN})()',rear);
  const actualSource=native(camera.position),actualTarget=native(camera.target),facing=camera.target.clone().sub(camera.position).normalize();
  rows.push({input,expected:{source:actualSource,target:actualTarget,heading:Math.atan2(facing.x,-facing.z),pitch:Math.asin(clamp(facing.y,-1,1)),fov:camera.fov,normalSource:native(normal),collisions}});
  // The production render loop restores these saved transforms after drawing.
  if(active)camera.position.copy(rear.o4.position);
 }
 cases.push({hz,initial,mode,rows});
}
fs.writeFileSync(process.argv[5],JSON.stringify({authority:'Actual bounded main9737 foot-follow and temporary look-behind wrapper; no retail runtime',cases}));
console.log('Actual foot look-behind reference:',cases.length,'scenarios',cases.reduce((n,c)=>n+c.rows.length,0),'frames');
'''

def main():
 chunks=ROOT/'local-only/site/_next/static/chunks'
 main=next(p for p in chunks.glob('*.js') if 'yM=[...wD.c$,24]' in p.read_text())
 vehicle=next(p for p in chunks.glob('*.js') if '98726:(e,t,l)' in p.read_text())
 metadata=ROOT/'local-only/site/game/native/camera.json'
 out=Path(os.environ.get('ZGTASA_CAMERA_REPORT_DIR',str(ROOT/'local-only/research/foot-look-behind')));out.mkdir(parents=True,exist_ok=True)
 # Reuse the established actual follow reference setup, not its generated data.
 head,tail=CAMERA_REFERENCE.split('const context=',1)
 # Run the wrapper with the shipped vector class, including divideScalar.
 begin=head.index('class V{');end=head.index('const f32=',begin)
 head=head[:begin]+'const {archivedModules}=require('+json.dumps(str(ROOT/'smoke_vehicle_dynamics'))+');const V=archivedModules()(85339).Pq0;\n'+head[end:]
 setup='const context='+tail.split('const feet=[]',1)[0]
 js=head+'\nfunction setup(){'+setup+';return {context,camera};}\n'+REPLAY
 with tempfile.TemporaryDirectory(prefix='run-',dir=out) as temporary:
  work=Path(temporary);(work/'reference.js').write_text(js)
  subprocess.run(['node',str(work/'reference.js'),str(main),str(vehicle),str(metadata),str(out/'reference.json')],check=True)
  sources=[ROOT/'ios/App/ServerAddress.swift',ROOT/'ios/App/NativeGameCamera.swift',ROOT/'smoke_native_foot_look_behind.swift']
  (work/'main.swift').write_text('\n'.join(p.read_text() for p in sources))
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'main.swift'),str(metadata),str(out/'reference.json'),str(out/'report.json')],check=True)
  (out/'source-hashes.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [main]+sources},indent=2)+'\n')
if __name__=='__main__':main()
