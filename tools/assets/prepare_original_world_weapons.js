#!/usr/bin/env node
'use strict';
// Export numeric weapon/slot/timing resources from the owner's local browser
// archive. This command never fetches a game package or publishes resources.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=require('node:path').resolve(__dirname, '../..'),args=process.argv.slice(2);let output='local-only/original-world-assets/game/native/original-weapons.json';
if(args.length){assert(args.length===2&&args[0]==='--output','Usage: node tools/assets/prepare_original_world_weapons.js [--output local-only/.../original-weapons.json]');output=args[1];}
const destination=path.resolve(root,output),privateRoot=path.join(root,'local-only');
assert(destination.startsWith(privateRoot+path.sep),'Output must stay inside this project local-only directory');
for(let current=destination;current!==privateRoot;current=path.dirname(current)){
 if(fs.existsSync(current))assert(!fs.lstatSync(current).isSymbolicLink(),'Output must not traverse a symlink');
}
const directory=path.join(privateRoot,'site/_next/static/chunks'),file=fs.readdirSync(directory).find(n=>n.startsWith('9737.')&&n.endsWith('.js'));
assert(file,'Owner-local archived browser source required');
const load=require('../../tests/vehicles/smoke_vehicle_dynamics').archivedModules(),api=load(60662),definitions=[];
for(let id=0;id<=46;id++){const value=api.U1(id);if(!value)continue;
 definitions.push({id:value.id,slot:value.slot,capacity:value.clip,kind:value.kind,wait:value.pace?.wait??0,reload:value.pace?.reload??0});
}
assert(definitions.length>30&&api._f===13,'Unrecognized original weapon policy');
fs.mkdirSync(path.dirname(destination),{recursive:true});
const doc={schema:1,protocol:38,sourceSHA256:crypto.createHash('sha256').update(fs.readFileSync(path.join(directory,file))).digest('hex'),definitions};
fs.writeFileSync(destination,JSON.stringify(doc)+'\n',{mode:0o600});console.log('Prepared owner-local original weapon policy:',definitions.length,'definitions');
