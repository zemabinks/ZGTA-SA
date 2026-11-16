#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),vm=require('node:vm');
const {spawn}=require('node:child_process');
const [gameRoot,executable,overlay,sourceRoot,reportPath]=process.argv.slice(2);
const game=require(path.join(gameRoot,'selfhost_backend.js'));
const source=fs.readFileSync(path.join(sourceRoot,'local-only/site/_next/static/chunks/7625.9f01e629ca3317ba.js'),'utf8');
const begin=source.indexOf("JSON.parse('",source.indexOf('80799:'))+12;
const table=JSON.parse(source.slice(begin,source.indexOf("')",begin)));
const browserModel=id=>table.find(row=>row.id===id&&row.model!=='null')?.model.toLowerCase()??null;
const projection=rows=>(rows??[]).map(row=>({number:Number(row[0]),name:row[1],code:row[2],
  skin:String(row[2]).startsWith('s')?Number(String(row[2]).slice(1)):row[31]}));
let browser,browserNumber=null,browserRows=[],browserFrames=0,child;
const nativeMessages=[];
const original=game.onMessage.bind(game);
game.onMessage=(peer,message)=>{
  if(message.t==='me'&&peer.player.number!==browserNumber)
    nativeMessages.push({number:peer.player.number,skin:message.skin,driving:message.driving===true});
  original(peer,message);
};
const json=(res,status,value)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(value));};
const files=new Map([['/game/native/models/index.json',path.join(overlay,'models/index.json')],
  ['/game/native/samp-skins.json',path.join(overlay,'samp-skins.json')]]);
const server=http.createServer(async(req,res)=>{
 try{
  const url=new URL(req.url,'http://fixture');
  if(files.has(url.pathname)){res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});return res.end(fs.readFileSync(files.get(url.pathname)));}
  if(url.pathname==='/__fixture'){
    if(req.method==='POST'){
      let text='';for await(const part of req)text+=part;
      const input=JSON.parse(text);
      browser.send(JSON.stringify({t:'me',walking:!input.driving,driving:!!input.driving,skin:input.skin,
        car:'411.0.0.0.',x:1481,y:-1738,z:13,health:1000}));
    }
    return json(res,200,{browserNumber,browserFrames,browserRows,nativeMessages:nativeMessages.slice(-3),
      currentRows:projection([...game.peers].map(peer=>game.row(peer)).filter(Boolean))});
  }
  return await game.http(req,res);
 }catch(error){json(res,500,{error:String(error.message)});}
});
server.on('upgrade',(req,socket,head)=>game.upgrade(req,socket,head));
const wait=async(condition,message)=>{const limit=Date.now()+8000;while(!condition()&&Date.now()<limit)await new Promise(r=>setTimeout(r,20));if(!condition())throw Error(message);};
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const base='http://127.0.0.1:'+server.address().port;
 browser=new WebSocket(base.replace('http:','ws:')+'/api/world/live');
 browser.addEventListener('message',event=>{
  try{const packet=JSON.parse(String(event.data));
   if(packet.t==='all'&&Number.isInteger(packet.number))browserNumber=packet.number;
   if(packet.t==='cars'){browserRows=projection(packet.c);browserFrames++;}
  }catch{}
 });
 await new Promise((resolve,reject)=>{browser.addEventListener('open',resolve,{once:true});browser.addEventListener('error',reject,{once:true});});
 browser.send(JSON.stringify({t:'hi'}));await wait(()=>browserNumber!==null,'Headless browser peer not ready');
 child=spawn(executable,[base],{stdio:['ignore','pipe','pipe']});let stdout='',stderr='';
 child.stdout.on('data',data=>stdout+=data);child.stderr.on('data',data=>stderr+=data);
 const code=await new Promise(resolve=>child.once('exit',resolve));
 const records=nativeMessages.map(row=>({...row,browserModel:browserModel(row.skin)}));
 fs.writeFileSync(reportPath,JSON.stringify({status:code===0?'PASS':'FAIL',nativeWebSocketMessages:records,
   browserReceivedFrames:browserFrames,aliases:[149,293].map(id=>({id,browserModel:browserModel(id)})),
   metadataURLs:[...files.keys()],stdout,stderr,scope:'Isolated actual network only; no rendered client or SA-MP UDP test'},null,2)+'\n');
 process.stdout.write(stdout);process.stderr.write(stderr);process.exitCode=code||0;
})().catch(error=>{console.error(error.message);process.exitCode=1;}).finally(()=>{
 child?.kill();browser?.close();server.close();game.flushSync();
 setTimeout(()=>process.exit(process.exitCode||0),150).unref();
});
