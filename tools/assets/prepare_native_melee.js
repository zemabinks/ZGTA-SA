#!/usr/bin/env node
// Original metadata stays in a project-local overlay, never the shared archive.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {archivedModules}=require('../../tests/vehicles/smoke_vehicle_dynamics');
const directory=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/_next/static/chunks');
const source={};
for(const name of fs.readdirSync(directory)){
 if(!name.endsWith('.js'))continue;const bytes=fs.readFileSync(path.join(directory,name));
 if(/(?:60662|27436|7436):\(/.test(bytes.toString()))source[name]=crypto.createHash('sha256').update(bytes).digest('hex');
}
const output=path.join(require('node:path').resolve(__dirname, '../..'),'local-only/native/melee.json');
if(process.argv.includes('--if-needed')){
 try{const prior=JSON.parse(fs.readFileSync(output));if(prior.version===1&&JSON.stringify(prior.source)===JSON.stringify(source)&&prior.weapons?.length===16){console.log('Native melee metadata current');process.exit(0)}}catch{}
}
const load=archivedModules(),weapons=load(60662),rows=[];
for(let id=0;id<=15;id++){
 const value=weapons.U1(id);if(value?.use!=='melee'||!value.combo)throw Error('Missing original melee profile '+id);
 rows.push({id,range:value.range,blocks:value.blocks,combo:value.combo,moving:value.moving?.blow??null,ground:value.ground?.blow??null});
}
fs.mkdirSync(path.dirname(output),{recursive:true});
fs.writeFileSync(output,JSON.stringify({version:1,authority:'Archived60662.U1 metadata; source data agrees with owner PC melee.dat, retail runtime unverified',weapons:rows,source})+'\n',{mode:0o600});
console.log('Prepared',rows.length,'original melee profiles in local-only/native/melee.json');
