// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Bounded, independent admission seams for one owner-supplied archive.
// No original implementation is stored here or rewritten on disk.
const crypto=require('node:crypto');
const MARKER='onTeleport:e=>{',LENGTH=300;
const SHA256='4c220ab7e2e69fc465391bf5ce6501dd18108051c4e3ad6a71f42a70d953dd2b';
const TOKEN='normal-teleport-and-entry-v2';
const TARGETS=Object.freeze([
  Object.freeze({kind:'teleport',marker:MARKER,length:LENGTH,sha256:SHA256}),
  Object.freeze({kind:'entry',marker:'mE=async()=>{',length:1052,
    sha256:'2193f96439d28e2214e1ca30d359519906a9ca67f15ca89273d2b671ced1be08'}),
  Object.freeze({kind:'entry',marker:'mR=async e=>{',length:475,
    sha256:'90f18893f5f1907468a6d2ed82c86e8db9b762f7a3ceaed6ffe0f8a9464cbccf'}),
]);
function instrument(source,targets=TARGETS){
  if(typeof source!=='string'||Buffer.byteLength(source)>32*1024*1024)
    throw Error('Browser recovery: local client exceeds the supported source bound.');
  if(!Array.isArray(targets)||!targets.length||targets.length>3)
    throw Error('Browser recovery: invalid callback identity set.');
  // Validate every seam before emitting registration or any modified source.
  const patches=targets.map(identity=>{
    const start=source.indexOf(identity.marker);
    if(start<0||source.indexOf(identity.marker,start+1)!==-1)
      throw Error('Browser recovery: a supported callback was not found exactly once.');
    const end=start+identity.length,body=source.slice(start,end);
    if(!body.endsWith('}')||crypto.createHash('sha256').update(body).digest('hex')!==identity.sha256)
      throw Error('Browser recovery: local client callback differs from the verified archive. Restore the matching archive.');
    let replacement;
    if(identity.kind==='teleport')replacement=body.slice(0,-1)+';globalThis.ZGTABrowserRecovery?.didApplyTeleport(e)}';
    else if(identity.kind==='entry'){
      const guard='if(mC=!1,';
      if(body.split(guard).length!==2||body.includes('_zgtaEntryGrant'))
        throw Error('Browser recovery: entry admission boundary differs from the verified archive.');
      const open=body.indexOf('{')+1;
      replacement=body.slice(0,open)+
        'const _zgtaEntryGrant=globalThis.ZGTABrowserRecovery?.captureActionGrant?.();if(_zgtaEntryGrant===null)return;'+body.slice(open);
      replacement=replacement.replace(guard,guard+
        'globalThis.ZGTABrowserRecovery?.isActionGrantCurrent?.(_zgtaEntryGrant)===false||');
    }else throw Error('Browser recovery: unsupported callback kind.');
    return{start,end,replacement};
  }).sort((a,b)=>b.start-a.start);
  for(let i=1;i<patches.length;i++)if(patches[i].end>patches[i-1].start)
    throw Error('Browser recovery: overlapping callback identities.');
  let result=source;
  for(const patch of patches)result=result.slice(0,patch.start)+patch.replacement+result.slice(patch.end);
  return `globalThis.ZGTABrowserRecovery?.registerHook(${JSON.stringify(TOKEN)});\n`+result;
}
module.exports={instrument,MARKER,LENGTH,SHA256,TOKEN,TARGETS};
