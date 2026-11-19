#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Optional experimental local mirror preparation. Never modifies its input.
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const hash=x=>crypto.createHash('sha256').update(x).digest('hex');
function patch(source){
 const marker='(0,fd.wl)(A.built,T.steer,';
 const at=source.indexOf(marker);
 if(at<0||source.indexOf(marker,at+1)>=0)throw Error('Pinned remote wheel call is missing or ambiguous');
 const open=at+'(0,fd.wl)'.length;let depth=0,quote=null,escape=false,end=-1;
 for(let n=open;n<source.length;n++){
  const ch=source[n];
  if(quote){if(escape)escape=false;else if(ch==='\\')escape=true;else if(ch===quote)quote=null;continue}
  if(ch==='"'||ch==="'"){quote=ch;continue}
  if(ch==='(')depth++;else if(ch===')'&&--depth===0){end=n+1;break}
 }
 if(end<0||source[end]!==',')throw Error('Pinned remote pose expression boundary changed');
 const hook=',globalThis.ZGTARemoteSuspension.apply(A.built,A.group,R)';
 return source.slice(0,end)+hook+source.slice(end);
}
function prepare({input,expectedSHA256,output}){
 if(!/^[a-f0-9]{64}$/.test(expectedSHA256||''))throw Error('Exact owner bundle SHA256 required');
 const original=fs.realpathSync(input),destination=path.resolve(output),privateRoot=path.resolve(require('node:path').resolve(__dirname, '../..'),'local-only/research');
 if(!destination.startsWith(privateRoot+path.sep)||destination===original)throw Error('Output must be a new ignored local-only/research file');
 const expectedPrivate=path.join(fs.realpathSync(require('node:path').resolve(__dirname, '../..')),'local-only','research');
 let ancestor=path.dirname(destination);while(!fs.existsSync(ancestor)){const parent=path.dirname(ancestor);if(parent===ancestor)throw Error('Output has no safe parent');ancestor=parent}
 const realAncestor=fs.realpathSync(ancestor);
 const expectedDestination=path.join(fs.realpathSync(require('node:path').resolve(__dirname, '../..')),path.relative(require('node:path').resolve(__dirname, '../..'),destination));
 if(path.resolve(realAncestor,path.relative(ancestor,destination))!==expectedDestination)throw Error('Output ancestor escapes private research');
 fs.mkdirSync(path.dirname(destination),{recursive:true});
 const realParent=fs.realpathSync(path.dirname(destination));
 if(fs.realpathSync(privateRoot)!==expectedPrivate||(realParent!==expectedPrivate&&!realParent.startsWith(expectedPrivate+path.sep)))throw Error('Output parent escapes private research');
 if(fs.existsSync(destination))throw Error('Output already exists; use a fresh versioned overlay');
 const bytes=fs.readFileSync(original);if(bytes.length>32*1024*1024||hash(bytes)!==expectedSHA256)throw Error('Owner bundle size/SHA mismatch');
 const text=bytes.toString('utf8');if(Buffer.from(text).compare(bytes)!==0)throw Error('Invalid bundle encoding');
 const adapter=fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'browser_remote_suspension.js'),'utf8');
 const prepared=Buffer.from(adapter+'\n'+patch(text));
 fs.writeFileSync(destination,prepared,{flag:'wx',mode:0o600});
 const report={identity:'zgta-remote-suspension-v1',inputSHA256:hash(bytes),adapterSHA256:hash(adapter),outputSHA256:hash(prepared),bytes:prepared.length,
  limitation:'Private optional overlay only; hosting/adoption and real browser pixels are separate. Static contact required, unknown collision coverage never fabricates a floor.'};
 fs.writeFileSync(destination+'.provenance.json',JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});return report;
}
if(require.main===module){
 const args=process.argv.slice(2);if(args.length!==3)throw Error('Usage: node tools/assets/prepare_browser_remote_suspension.js INPUT.js EXPECTED_SHA256 NEW_PRIVATE_OUTPUT.js');
 console.log(JSON.stringify(prepare({input:args[0],expectedSHA256:args[1],output:args[2]}),null,2));
}
module.exports={patch,prepare};
