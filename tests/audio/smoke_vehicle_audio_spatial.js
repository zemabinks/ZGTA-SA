#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {archivedModules}=require('../vehicles/smoke_vehicle_dynamics');
function original() {
  const load=archivedModules(),source=load.factories[1061].toString(),meta=load(35409),three=load(85339);
  const begin=source.indexOf('let i=e.map(',source.indexOf('hear(e,t)'))+6;
  const end=source.indexOf(';for(let e of[...eI.keys()]',begin);
  assert(begin>5&&end>begin);
  const select=Function('a','return(e,t)=>('+source.slice(begin,end)+');')(meta);
  class Param {constructor(value=0){this.value=value;}setTargetAtTime(value){this.value=value;}setValueAtTime(value){this.value=value;}cancelScheduledValues(){} }
  class Node {constructor(){this.gain=new Param(1);this.playbackRate=new Param(1);this.positionX=new Param();this.positionY=new Param();this.positionZ=new Param();}connect(to){return to;}disconnect(){}start(){}stop(){} }
  let active;
  class Context {
    constructor(){active=this;this.state='running';this.currentTime=0;this.panners=[];this.listener={};for(const key of ['positionX','positionY','positionZ','forwardX','forwardY','forwardZ'])this.listener[key]=new Param();}
    createGain(){return new Node();}createBufferSource(){return new Node();}
    createPanner(){const node=new Node();node.refDistance=1;node.maxDistance=10000;node.rolloffFactor=1;this.panners.push(node);return node;}
    close(){return Promise.resolve();}decodeAudioData(){return Promise.resolve({duration:1});}
  }
  const exports={},depend=id=>id===31753?{holdAway:x=>x,wake(){}}:load(id);depend.d=load.d;
  const factory=Function('window','performance','fetch','setTimeout','return('+source+');')({AudioContext:Context},{now:()=>100000},()=>Promise.resolve({ok:false}),()=>0);
  factory({},exports,depend);
  return {meta,three,select,construct:exports.j,context:()=>active};
}
function main(){
  const {meta,three,select,construct,context}=original();
  const catalogue={road:Object.keys(meta.U2).map(Number),aircraft:Object.keys(meta.B$).map(Number),boats:Object.keys(meta.eo).map(Number),special:Object.keys(meta.i0).map(Number),trains:Object.keys(meta.KX).map(Number)};
  const models=[420,487,539,457,537,538,430,464,400,593,592,999];
  const scenes=[];
  for(let scene=0;scene<60;scene++){
    const listener=[Math.sin(scene)*30,Math.cos(scene)*20,scene],forward=[Math.sin(scene/10),Math.sin(scene/20)*.6,-Math.cos(scene/10)];
    const candidates=[];
    for(let i=0;i<90;i++){
      const distance=[0,6.99,7,48,109.999,110,329.999,330,400][(i+scene)%9],angle=(i*2.399963229728653)+scene;
      candidates.push({id:`s${scene}-car${i}`,model:models[(i+scene)%models.length],position:[listener[0]+distance*Math.cos(angle),listener[1]+(i%5-2),listener[2]+distance*Math.sin(angle)],speed:Math.sin(i)*20});
    }
    const input=candidates.map(c=>({...c,car:c.model,position:new three.Pq0(...c.position)}));
    const expected=select(input,{position:new three.Pq0(...listener)});
    const audio=construct();audio.hear(input,{position:new three.Pq0(...listener),forward:new three.Pq0(...forward)});
    const configs=context().panners.map(p=>({reference:p.refDistance,maximum:p.maxDistance,rolloff:p.rolloffFactor}));
    assert.equal(Object.keys(audio.state().others).length,expected.length);
    scenes.push({listener,forward,candidates,selected:expected.map(row=>({id:row.car.id,distance:row.away})),configs});
    audio.dispose();
  }
  // W3C §6.2/6.3.1 and DistanceModelType.inverse reference equations.
  const spatial=[];
  for(let i=0;i<800;i++) {
    const listener=[Math.sin(i)*4,2,Math.cos(i)*5],forward=[Math.sin(i/20),Math.sin(i/30),-Math.cos(i/20)];
    const source=[Math.cos(i/3)*70,Math.sin(i/10)*12,Math.sin(i/3)*70];
    const relative=new three.Pq0(...source).sub(new three.Pq0(...listener)).normalize(),f=new three.Pq0(...forward),right=f.clone().cross(new three.Pq0(0,1,0)).normalize(),up=right.clone().cross(f.clone().normalize());
    const projected=relative.clone().sub(up.clone().multiplyScalar(relative.dot(up))).normalize();
    let azimuth=180*Math.acos(Math.max(-1,Math.min(1,projected.dot(right))))/Math.PI;
    if(projected.dot(f.clone().normalize())<0)azimuth=360-azimuth;
    azimuth=azimuth>=0&&azimuth<=270?90-azimuth:450-azimuth;
    let angle=Math.max(-180,Math.min(180,azimuth));if(angle< -90)angle=-180-angle;else if(angle>90)angle=180-angle;
    const matrices=[true,false].map(mono=>{const x=mono?(angle+90)/180:angle<=0?(angle+90)/90:angle/90,l=Math.cos(x*Math.PI/2),r=Math.sin(x*Math.PI/2);return mono?[l,0,r,0]:angle<=0?[1,l,0,r]:[l,0,r,1];});
    spatial.push({listener,forward,source,azimuth,matrices});
  }
  const directory=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/vehicle-audio-fixtures');fs.mkdirSync(directory,{recursive:true});
  fs.writeFileSync(path.join(directory,'spatial.json'),JSON.stringify({catalogue,scenes,spatial}),{mode:0o600});
  console.log(`Recorded original remote selection and panner configuration: ${scenes.length} scenes / ${spatial.length} W3C spatial cases`);
}
if(require.main===module)main();
