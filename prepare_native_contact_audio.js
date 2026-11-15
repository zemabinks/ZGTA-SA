#!/usr/bin/env node
// Recover material and water-contact routing from the archived public client.
// Generated routing and samples stay on the host Mac under local-only/.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {archivedModules}=require('./smoke_vehicle_dynamics');
function main(){
 const load=archivedModules(),materials=load(77287),client=load.factories[19737].toString();
 const splash=client.match(/\bkU=(\[[0-9,]+\])/);
 if(!splash)throw Error('Original contact splash routing unavailable');
 const document={version:1,materials:Array.from({length:load(35409).XP.length},(_,id)=>materials.Kk(id)),
  defaults:materials.aM,steps:materials.RZ,samples:Array.from({length:256},(_,id)=>id).filter(id=>materials.rG('39_'+id)),
  splashes:JSON.parse(splash[1]),source:{materials:crypto.createHash('sha256').update(load.factories[77287].toString()).digest('hex'),
   contact:crypto.createHash('sha256').update(client.slice(client.indexOf('cv=function'),client.indexOf('cb.wet.hear(cv.wet)'))).digest('hex')}};
 const output=path.join(__dirname,'local-only/site/game/native/contact-audio.json');
 fs.writeFileSync(output,JSON.stringify(document)+'\n',{mode:0o600});
 console.log('Prepared',document.materials.length,'original material contact profiles and',document.samples.length,'declared collision samples locally');
}
if(require.main===module)main();
module.exports={main};
