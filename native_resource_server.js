// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const fs=require('node:fs'),path=require('node:path');

function create({localOnly}) {
  const directory=path.resolve(localOnly),catalog=path.join(directory,'resources-v1/catalog.json');
  const roots=['site/game','site/reference/weapons','site/tools/map','native-working/models','native','original-world-assets/game/native','resources-v1/generated'].map(p=>path.join(directory,p));
  const configuration=path.join(directory,'resource-source-roots.json');
  if(fs.existsSync(configuration)){
    const data=fs.readFileSync(configuration);if(data.length>131072)throw Error('Invalid resource source-root configuration');
    const extra=JSON.parse(data);if(!Array.isArray(extra)||extra.length>32||extra.some(p=>typeof p!=='string'||!path.isAbsolute(p)||path.dirname(path.resolve(p))===path.resolve(p)))throw Error('Invalid resource source-root configuration');
    roots.push(...extra);
  }
  const approved=roots.flatMap(p=>{try{const real=fs.realpathSync(p);return fs.statSync(real).isDirectory()?[real+path.sep]:[];}catch{return [];}});
  const digest=/^[a-f0-9]{64}$/;
  let cached=null,signature=null;
  const cjPrefix='/game/native/cj-normal-vest-denim-v1/';
  const cjFiles=new Set(['profile.json','player.dff','vest.dff','head.dff','hands.dff','jeans.dff','sneaker.dff',
    'player_torso.txd','vest.txd','player_face.txd','jeansdenim.txd','sneakerbincblk.txd','clothes.dat']);
  const matches=p=>p==='/game/native/resource-manifest.json'||p.startsWith('/game/native/resource-blobs/')||p.startsWith(cjPrefix);
  function handle(req,res,pathname){
    if(!['GET','HEAD'].includes(req.method)){res.writeHead(405,{Allow:'GET, HEAD'});res.end();return;}
    let data;
    try{
      const stat=fs.statSync(catalog);if(stat.size>96*1024*1024)throw Error('Oversized resource catalogue');
      const revision=[stat.ino,stat.size,stat.mtimeMs,stat.ctimeMs].join(':');
      data=revision===signature?cached:JSON.parse(fs.readFileSync(catalog,'utf8'));
      if(data.manifest?.schema!==1||data.manifest?.profile!=='zgta-prepared-v1'||!digest.test(data.manifest.contentID)||!data.files)throw Error('Invalid resource catalogue');
      cached=data;signature=revision;
    }catch{
      res.writeHead(pathname.startsWith(cjPrefix)?404:503,{'Content-Type':'text/plain; charset=utf-8'});res.end('Prepare the Mac resource index with prepare_native_resource_package.py');return;
    }
    if(pathname==='/game/native/resource-manifest.json'){
      const bytes=Buffer.from(JSON.stringify(data.manifest));res.writeHead(200,{'Content-Type':'application/json','Content-Length':bytes.length,'Cache-Control':'no-cache'});res.end(req.method==='HEAD'?undefined:bytes);return;
    }
    let key;
    if(pathname.startsWith(cjPrefix)){
      if(!cjFiles.has(pathname.slice(cjPrefix.length))){res.writeHead(404);res.end();return;}
      const records=Array.isArray(data.manifest.resources)?data.manifest.resources.filter(item=>item&&item.path===pathname.slice(1)):null;
      if(!Array.isArray(records)||records.length!==1){res.writeHead(404);res.end();return;}
      key=records[0].sha256;
    }else{key=pathname.slice('/game/native/resource-blobs/'.length);}
    const item=digest.test(key)&&data.files[key];
    if(!item||typeof item.path!=='string'||!Number.isSafeInteger(item.bytes)||item.bytes<=0||item.bytes>2147483648){res.writeHead(404);res.end();return;}
    const file=path.resolve(item.path);
    let real;try{real=fs.realpathSync(file);}catch{res.writeHead(404);res.end();return;}
    if(!approved.some(root=>real.startsWith(root))){res.writeHead(403);res.end();return;}
    fs.stat(real,(error,stat)=>{
      if(error||!stat.isFile()||stat.size!==item.bytes){res.writeHead(409);res.end('Resource changed; refresh the prepared index');return;}
      res.writeHead(200,{'Content-Type':'application/octet-stream','Content-Length':stat.size,'Cache-Control':'public, max-age=31536000, immutable','ETag':'"'+key+'"','X-ZGTA-Resource-SHA256':key});
      if(req.method==='HEAD'){res.end();return;}
      const stream=fs.createReadStream(real);stream.on('error',()=>res.destroy());res.on('close',()=>stream.destroy());stream.pipe(res);
    });
  }
  return {matches,handle};
}
module.exports={create};
