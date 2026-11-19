#!/usr/bin/env node
'use strict';
const http=require('node:http'),crypto=require('node:crypto'),{spawn}=require('node:child_process'),assert=require('node:assert/strict');
const dff=Buffer.from('ZGTA independent synthetic DFF transfer fixture. '.repeat(90)),txd=Buffer.from('ZGTA independent synthetic TXD transfer fixture. '.repeat(40));
let requests=0,active=0,maxActive=0,done=false;const sockets=new Set(),counts={};
const server=http.createServer((req,res)=>{
 requests++;counts[req.url]=(counts[req.url]??0)+1;assert.equal(req.headers['user-agent'],'SAMP/0.3');assert(!req.headers.cookie&&!req.headers.authorization);active++;maxActive=Math.max(maxActive,active);res.on('close',()=>active--);
 if(req.url==='/redirect'){res.writeHead(302,{Location:'/dff','Set-Cookie':'fixture=must-not-leak'});res.end();return}
 if(req.url==='/loop'){res.writeHead(302,{Location:'/loop'});res.end();return}
 if(req.url==='/error'){res.writeHead(403);res.end();return}
 if(req.url==='/wrong-size'){res.writeHead(200,{'Content-Length':dff.length+1});res.end(Buffer.concat([dff,Buffer.from([1])]));return}
 if(req.url==='/oversize'){res.writeHead(200,{'Transfer-Encoding':'chunked'});res.write(dff);res.end(Buffer.from([1]));return}
 if(req.url==='/bad'){const data=Buffer.from(dff);data[0]^=1;res.writeHead(200,{'Content-Length':data.length});res.end(data);return}
 if(req.url==='/slow'){res.writeHead(200,{'Content-Length':dff.length});res.write(dff.subarray(0,1));const timer=setTimeout(()=>res.end(dff.subarray(1)),2000);res.on('close',()=>clearTimeout(timer));return}
 const bytes=req.url==='/txd'?txd:dff;res.writeHead(200,{'Content-Length':bytes.length});res.end(bytes);
});
server.on('connection',s=>{sockets.add(s);s.on('close',()=>sockets.delete(s))});
server.listen(0,'127.0.0.1',()=>{
 const metadata=Buffer.from(JSON.stringify({dff:dff.toString('hex'),txd:txd.toString('hex'),dffMD5:crypto.createHash('md5').update(dff).digest('hex'),txdMD5:crypto.createHash('md5').update(txd).digest('hex')})).toString('base64');
 const child=spawn(process.argv[2],[process.argv[3],'http://127.0.0.1:'+server.address().port,process.argv[4],metadata],{stdio:'inherit'});
 child.on('exit',(code,signal)=>{done=true;for(const s of sockets)s.destroy();server.close();assert.equal(code,0,'Swift artwork fixture '+signal);assert.equal(counts['/dff'],4,'Initial, corrupt-cache recovery, redirect and post-cancel transfer');assert.equal(counts['/loop'],5,'Bounded redirects');assert.equal(counts['/bad'],1);assert.equal(counts['/wrong-size'],1);assert.equal(counts['/oversize'],1);assert(maxActive<=2,'Two bounded active downloads');console.log('PASS artwork HTTP fixture:',requests,'real HTTP requests; cookies/credentials absent, redirects and concurrency bounded')});
});
setTimeout(()=>{if(!done){for(const s of sockets)s.destroy();server.close();throw Error('Artwork fixture timeout')}},45000).unref();
