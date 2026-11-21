#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual resource module and loopback HTTP, authored bytes/catalogue only.
const assert=require('node:assert/strict'),fs=require('node:fs'),http=require('node:http'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const directory=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-icon-http-')),local=path.join(directory,'local-only');
let server;
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
async function main(){
 const icons=path.join(local,'native-weapon-icons'),resources=path.join(local,'resources-v1');fs.mkdirSync(icons,{recursive:true});fs.mkdirSync(resources);
 const file=path.join(icons,'25.png'),catalog=path.join(resources,'catalog.json');
 function install(bytes){fs.writeFileSync(file,bytes);const key=sha(bytes);fs.writeFileSync(catalog,JSON.stringify({manifest:{schema:1,profile:'zgta-prepared-v1',contentID:key,resources:[{path:'reference/weapons/25.png',bytes:bytes.length,sha256:key,required:false}]},files:{[key]:{path:file,bytes:bytes.length}}}));return key;}
 const bytes=Buffer.from('authored PNG transport bytes; image decode tested separately'),key=install(bytes);
 const owner=require('../../native_resource_server').create({localOnly:local});
 assert(owner.matches('/reference/weapons/25.png'));assert(!owner.matches('/reference/weapons/22.png'));assert(!owner.matches('/reference/weapons/47.png'));assert(!owner.matches('/reference/weapons/../25.png'));
 server=http.createServer((req,res)=>{if(owner.matches(req.url))owner.handle(req,res,req.url);else{res.writeHead(404);res.end();}});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const port=server.address().port;
 function request(route,method='GET'){return new Promise((resolve,reject)=>{const req=http.request({host:'127.0.0.1',port,path:route,method,agent:false},res=>{const data=[];res.on('data',b=>data.push(b));res.on('end',()=>resolve({status:res.statusCode,headers:res.headers,body:Buffer.concat(data)}));});req.on('error',reject);req.end();});}
 let r=await request('/reference/weapons/25.png');assert.equal(r.status,200);assert.equal(r.headers['content-type'],'image/png');assert.equal(r.headers['cache-control'],'no-cache');assert.equal(r.headers['x-zgta-resource-sha256'],key);assert.deepEqual(r.body,bytes);
 r=await request('/reference/weapons/25.png','HEAD');assert.equal(r.status,200);assert.equal(r.body.length,0);assert.equal(Number(r.headers['content-length']),bytes.length);
 r=await request('/reference/weapons/25.png','POST');assert.equal(r.status,405);
 r=await request('/game/native/resource-blobs/'+key);assert.equal(r.status,200);assert.equal(r.headers['content-type'],'application/octet-stream');assert.match(r.headers['cache-control'],/immutable/);assert.deepEqual(r.body,bytes);
 const changed=Buffer.from('changed authored icon transport');install(changed);r=await request('/reference/weapons/25.png');assert.equal(r.status,200);assert.deepEqual(r.body,changed);
 fs.appendFileSync(file,'changed-without-index');r=await request('/reference/weapons/25.png');assert.equal(r.status,409);
 fs.unlinkSync(catalog);assert(!owner.matches('/reference/weapons/25.png'),'Missing prepared catalogue shadowed archived PNG fallback');r=await request('/game/native/resource-manifest.json');assert.equal(r.status,503);
 console.log('PASS prepared weapon-icon HTTP: exact logical ID/bytes, GET/HEAD/type/cache, blob identity, refreshed index, changed-file rejection and legacy fallback; no image, App or external-auth claim');
}
main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{if(server)await new Promise(resolve=>server.close(resolve));fs.rmSync(directory,{recursive:true,force:true});});
