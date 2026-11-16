#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const T=require('./smoke_vehicle_dynamics').archivedModules()(85339);
const folder=path.join(__dirname,'local-only/site/_next/static/chunks'),file=fs.readdirSync(folder).find(n=>n.startsWith('9737.'));
const source=fs.readFileSync(path.join(folder,file),'utf8'),start=source.indexOf('mG=e=>{try{return function(e,t,l)'),a=source.indexOf('function(e,t,l)',start),b=source.indexOf('}(nw,nb,e)',a)+1;
assert(start>=0&&a>start&&b>a);
const scratch={d:T,j4:[.35,.72,1.08,1.4500000000000002],j6:[0,.15,.3,.45,.6,.8,1],j8:[1.3,1.6,2,2.5,3]};
for(const key of ['j9','Me','Mt','Ml','Mn','Mr'])scratch[key]=new T.Pq0();scratch.j7=new T.PTz();
const solve=vm.runInNewContext('('+source.slice(a,b)+')',scratch);
const rows=JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/site/game/native/vehicles.physics.json'),'utf8')).models,cases=[];
for(const [model,built] of Object.entries(rows))for(let poseIndex=0;poseIndex<8;poseIndex++)for(const mode of ['clear','leftWall','farOnly','narrow','roofOnly','blocked','void','slope']){
 const position=new T.Pq0(10.25,2.1,-20.5),quaternion=new T.PTz().setFromAxisAngle(new T.Pq0(0.3,1,0.2).normalize(),poseIndex*.71),side=poseIndex%2?-1:1;
 const low=built.bounds.box.min,high=built.bounds.box.max,seat=poseIndex%3===0?null:new T.Pq0(side*.35,low[1]+(high[1]-low[1])*.65,(low[2]+high[2])/2);
 const wanted=poseIndex%3===1?new T.Pq0(side*(Math.max(-low[0],high[0])+.65),built.origin-.9,.3).applyQuaternion(quaternion).add(position):null;
 let calls=[0,0,0];
 const world={below(p,d){calls[0]++;if(mode==='void')return null;let floor=mode==='slope'?.08*(p.x-10.25)-.04*(p.z+20.5):0,t=p.y-floor;return t>=0&&t<=d?t:null},along(p,way,d){calls[1]++;return mode==='leftWall'&&way.x<-.05?0.1:null}};
 const motor={fits(p,w){calls[2]++;switch(mode){case'leftWall':return p.x>10.6;case'farOnly':return Math.hypot(p.x-position.x,p.z-position.z)>3.2;case'narrow':return w===0;case'roofOnly':return p.y>position.y+3;case'blocked':return false;default:return true}}};
 const expected=solve(world,motor,{built,position,quaternion,seat,side,wanted,body:47,aboard:poseIndex===7});
 assert(expected&&expected.toArray().every(Number.isFinite));
 cases.push({model,poseIndex,mode,position:position.toArray(),rotation:quaternion.toArray(),seat:seat?.toArray()??null,side,wanted:wanted?.toArray()??null,aboard:poseIndex===7,expected:expected.toArray(),calls});
}
const out={sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),expressionSHA256:crypto.createHash('sha256').update(source.slice(a,b)).digest('hex'),cases};
fs.writeFileSync(process.argv[2],JSON.stringify(out)+'\n',{mode:0o600});console.log('Recorded actual archived exit planner:',cases.length,'cases across',Object.keys(rows).length,'models');
