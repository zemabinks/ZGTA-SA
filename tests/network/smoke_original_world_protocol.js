#!/usr/bin/env node
'use strict';
// Actual archived browser decoder is evaluated only from the owner's private
// archive. Neither its code nor generated goldens are included in source.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=require('node:path').resolve(__dirname, '../..'), folder=path.join(root,'local-only/site/_next/static/chunks');
const file=fs.readdirSync(folder).find(x=>x.startsWith('9737.')&&x.endsWith('.js'));
assert(file,'Owner-local archived browser chunk missing');const source=fs.readFileSync(path.join(folder,file),'utf8');
const start=source.indexOf('np=function(){let e=new Map,t=new Map,l=new TextDecoder'),end=source.indexOf('}(),nh=',start)+1;
assert(start>=0&&end>start);const expression=source.slice(start+3,end);
const make=()=>vm.runInNewContext('('+expression+')()',{TextDecoder,Map,DataView,ArrayBuffer,Uint8Array,Number,Math,Date});
const frame=(tag,p)=>Buffer.concat([p.length<128?Buffer.from([tag,p.length]):Buffer.from([tag,(p.length&127)|128,p.length>>7]),p]);
const u16=x=>{const b=Buffer.alloc(2);b.writeUInt16BE(x);return b}, u32=x=>{const b=Buffer.alloc(4);b.writeUInt32BE(x>>>0);return b};
const signed=(x,n)=>{const b=Buffer.alloc(n);b.writeIntBE(x,0,n);return b};
const byte=x=>Buffer.from([x]),num=(seed,k,range)=>((seed*7919+k*104729)%range)-Math.floor(range/2);
const base=()=>{let r=Array(44).fill(null);Object.assign(r,{0:'23',1:'QA browser peer',2:'s7',3:1,4:2,5:3,6:0,16:1760000000100,18:100,27:24,30:0,31:7});return r};
const baseline=()=>frame(1,Buffer.concat([u16(29),Buffer.from(JSON.stringify(base()))]));
const delta=(flags,seed,clock,stamp=29)=>{const parts=[u16(23),u16(stamp),u16(flags),u32(clock)];
 for(let k=0;k<3;k++)parts.push(signed(num(seed,k,4_000_000),4));
 const a=flags&4096?4:2;parts.push(signed(num(seed,3,a===4?2_000_000:60_000),a));if(flags&64)for(let k=4;k<6;k++)parts.push(signed(num(seed,k,a===4?2_000_000:60_000),a));
 for(let k=6;k<9;k++)parts.push(signed(num(seed,k,flags&256?1_000_000:60_000),flags&256?3:2));
 parts.push(u16(100+seed%1000),byte(seed%101));if(flags&128){parts.push(signed(num(seed,9,1_000_000),3));for(let k=10;k<14;k++)parts.push(signed(num(seed,k,60_000),2));parts.push(byte(100-seed%99));}
 if(flags&32)parts.push(u16(seed%65536));if(flags&512)parts.push(signed(num(seed,14,60_000),2));
 if(flags&1024){let n=seed%2?300:16384;do{const low=n&127;n=Math.floor(n/128);parts.push(byte(low|(n?128:0)));}while(n);}
 if(flags&2048)parts.push(byte(60+seed%3),byte(seed%4));if(flags&8192)parts.push(u16(seed%65536));
 if(flags&16384){const id=Buffer.from(seed%2?'vehicle-ä':'car');parts.push(byte(id.length),id);for(let k=15;k<18;k++)parts.push(signed(num(seed,k,4_000_000),4));}
 if(flags&32768){parts.push(byte(3));for(let k=18;k<21;k++)parts.push(signed(num(seed,k,4_000_000),4));}
 return frame(2,Buffer.concat(parts));};
const shot=(id=true)=>{const p=[u16(23),byte(24)];for(let i=0;i<6;i++)p.push(signed((i-3)*123456,4));p.push(byte(1));if(id)p.push(u16(55),byte(9));return frame(3,Buffer.concat(p));};
const masks=[0,65535,...Array.from({length:16},(_,i)=>1<<i),...Array.from({length:16},(_,i)=>65535^(1<<i))];let seed=0x12549;for(let i=0;i<512;i++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;masks.push(seed&65535);}
const cases=[];
for(let i=0;i<masks.length;i++){
 const wireClock=i%3===0?0xffffffb0:i%3===1?50:1234567890,anchor=4_294_967_296*411+(i%3===0?4_294_967_250:i%3===1?10:1234567800);
 const bytes=Buffer.concat([baseline(),delta(masks[i],i+1,wireClock),...(i%7===0?[shot(i%2===0)]:[])]);
 const decoder=make(),packets=[],shots=[];decoder.clock(anchor,1000);decoder.read(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),1100,r=>packets.push(JSON.parse(JSON.stringify(r))),s=>shots.push(s));
 assert(packets.length);cases.push({flags:masks[i],anchor,now:1100,data:bytes.toString('base64'),row:packets.at(-1).at(-1),shots});
}
const fixture={sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),expressionSHA256:crypto.createHash('sha256').update(expression).digest('hex'),cases};
fs.writeFileSync(process.argv[2],JSON.stringify(fixture)+'\n',{mode:0o600});console.log('Recorded',cases.length,'actual archived binary decoder cases');
