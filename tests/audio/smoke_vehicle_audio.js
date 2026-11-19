#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path');
const {archivedModules}=require('../vehicles/smoke_vehicle_dynamics');
function functionAt(source,start) {
  const brace=source.indexOf('{',start);let depth=0,quote=null,escaped=false;
  for(let i=brace;i<source.length;i++) {
    const c=source[i];if(quote){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c===quote)quote=null;continue;}
    if(c==='"'||c==="'"||c==='`'){quote=c;continue;}
    if(c==='{')depth++;else if(c==='}'&&!--depth)return source.slice(start,i+1);
  }throw Error('Missing original function');
}
function archivedAudio() {
  const load=archivedModules(),source=load.factories[1061].toString();
  const prefix=source.slice(source.indexOf('{')+1,source.indexOf('function eA'));
  const engine=functionAt(source,source.indexOf('eR=function(e,t,n,a)')+3);
  const remote=functionAt(source,source.indexOf('ea=function(e,t,n,a)',source.indexOf('hear(e,t)'))+3);
  const reverse=functionAt(source,source.indexOf('eU=function(e,t,n)')+3);
  const depend=id=>load(id);depend.d=()=>{};
  const api=Function('n','t',prefix+'return {reset:G,aircraft:N,boatState:J,boat:Q,skim:ee,specialState:ef,special:eg,train:ev,engine:('+engine+'),remote:('+remote+'),reverse:('+reverse+')};')(depend,{});
  return {load,api};
}
function generate() {
  const {load,api}=archivedAudio(),meta=load(35409),three=load(85339),cases=[];
  for(const model of [420,457,448,522,480]) {
    const table=load(87605).c_(model,new three.Pq0(2,1.8,5)).table;
    // Golf/single-gear branches are exercised with a source-provided road-bank
    // duration as an explicit synthetic configuration, not a model bank claim.
    const box=load(23895).Ux(table,model),bank=(meta.U2[model]??meta.U2[420])[0],sound=meta.e4[bank][0];
    const config={runUpDuration:sound[2]/sound[0],loopStart:Math.max(0,sound[1])/sound[0]};
    const state=api.reset({said:{}}),frames=[];
    for(let i=0;i<2400;i++) {
      const section=Math.floor(i/200),ratio=(i%200)/199,reverse=section===5;
      const speed=section===0?0:section===1?ratio*box.max*50:section===2?box.max*50:section===3?(1-ratio)*box.max*50:
        section===4?0:reverse?-ratio*box.reverse*50:section===6?5:section===7?20:section===8?25:section===9?40:section===10?15:0;
      const accel=[0,1,1,0,1,1,1,.7,1,1,.8,0][section];
      const input={id:model,speed,climb:section===7?8:section===8?-8:0,accel,brake:section===3?.8:0,
        handbrake:section===4,gear:reverse?0:Math.max(1,Math.min(box.count,1+Math.floor(Math.abs(speed)/Math.max(1,box.max*50)*box.count))),
        box,grounded:section===10?0:1,spin:section===4?ratio*12:0,lean:section===6?Math.sin(i/15):0,bike:model===522,nitro:section===9};
      const delta=[1/60,.02,.033,.005,.1,.25][i%6];
      const output=api.engine(state,delta,input,{runUp:config.runUpDuration,loop:config.loopStart});
      frames.push({delta,input,output:{...output}});
    }
    cases.push({model,config,frames});
  }
  const directory=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/vehicle-audio-fixtures');fs.mkdirSync(directory,{recursive:true});
  fs.writeFileSync(path.join(directory,'road.json'),JSON.stringify(cases),{mode:0o600});
  const auxiliary=[];
  for(const kind of ['heli','prop','jet'])for(const remote of [false,true]) {
    let pitch=-1;const frames=[];
    for(let i=0;i<1200;i++) {
      const input={rotor:(i%300)/250,throttle:Math.sin(i/71),health:[1000,640,450,380,200][Math.floor(i/240)],
        up:Math.cos(i/100),nose:Math.sin(i/45),side:Math.sin(i/60),behind:(1+Math.sin(i/120))/2,away:i%200};
      const delta=[1/60,.02,.033][i%3],random=(i%19)/19;
      const actual=api.aircraft([kind,85],input,pitch,delta,remote,()=>random);pitch=actual.pitch;
      frames.push({delta,input,random,pitch,layers:actual.layers.map(([name,sound,rate,gain])=>({name,sound,rate,gain}))});
    }auxiliary.push({kind,remote,bank:85,frames});
  }
  for(const kind of ['golf','rcCar','rcPlane','rcHeli','hover','train','tram']) {
    const state=api.specialState(),frames=[];
    for(let i=0;i<1200;i++) {
      const input={share:(i%300)/250,speed:Math.sin(i/140)*65,accel:i%300<200?1:0,brake:i%300>=150?.8:0,
        rotor:i%4===0?null:(i%200)/500,up:Math.cos(i/120),nose:Math.sin(i/45),side:Math.sin(i/60),mine:i%400<300};
      const sourceInput={...input};if(input.rotor===null)delete sourceInput.rotor;
      const delta=[1/60,.02,.033][i%3],bank=kind==='tram'?133:131;
      const layers=kind==='train'||kind==='tram'?api.train(state,delta,[132,bank],sourceInput):api.special(state,delta,[kind,77,-1,1],sourceInput);
      frames.push({delta,input,pitch:state.pitch,twin:state.twin,turned:state.turned,
        layers:layers.map(([name,sound,rate,db])=>({name,sound,rate,gain:10**(db/20)}))});
    }auxiliary.push({kind,bank:kind==='tram'?133:kind==='train'?131:77,frames});
  }
  {
    const state=api.boatState(),frames=[];
    for(let i=0;i<2400;i++) {
      const delta=[1/60,.02,.033][i%3],input={throttle:Math.sin(i/200),afloat:i%400<300,up:Math.cos(i/120),distance:i%300,speed:Math.sin(i/140)*45};
      const out=api.skim(input.speed,input.afloat,input.distance,api.boat(state,delta,input.throttle,input.afloat,input.up,input.distance,{}));
      frames.push({delta,input,pitch:state.pitch,turning:state.turning,layers:[{name:'engine',sound:'21_0',rate:out.engineRate,gain:out.engine},{name:'skim',sound:'39_3',rate:out.skimRate,gain:out.skim}]});
    }auxiliary.push({kind:'boat',bank:21,frames});
  }
  for(const model of [420,457]) {
    const state={state:0,fadeIn:1,fadeOut:1,said:{}},frames=[];
    for(let i=0;i<1200;i++) {
      const delta=[1/60,.02,.033][i%3],input={share:Math.sin(i/100)**2};
      const out=api.remote(state,delta,model,input.share);
      const layers=[];
      for(const [name,index,rate,gain]of[['idle',1,out.idleRate,out.idle],['revs',0,out.revsRate,out.revs]])
        if(gain>-Infinity)layers.push({name,sound:'86_'+index,rate,gain:10**(gain/20)});
      frames.push({delta,input,pitch:0,layers});
    }auxiliary.push({kind:'remote',model,bank:86,frames});
  }
  {
    const state={pedal:0,grounded:0,said:{}},frames=[];
    for(let i=0;i<1200;i++) {
      const delta=[1/60,.02,.033][i%3],input={gas:Math.sin(i/100),speed:Math.sin(i/100)*20,gear:i%400<300?0:1,grounded:i%500<400?1:0,box:{reverse:.4}};
      const out=api.reverse(state,delta,input),layers=out.sound?[{name:'reverse',sound:out.sound,rate:out.rate,gain:10**(out.loud/20)}]:[];
      frames.push({delta,input,pitch:0,layers});
    }auxiliary.push({kind:'reverse',bank:0,frames});
  }
  fs.writeFileSync(path.join(directory,'auxiliary.json'),JSON.stringify(auxiliary),{mode:0o600});
  console.log(JSON.stringify({cases:cases.length,frames:cases.reduce((n,c)=>n+c.frames.length,0)}));
}
if(require.main===module)generate();
module.exports={archivedAudio,functionAt};
