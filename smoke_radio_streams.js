#!/usr/bin/env node
const fs=require('node:fs'), path=require('node:path'), assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const {Writable}=require('node:stream');
const {archivedModules}=require('./smoke_vehicle_dynamics');
const streams=require('./radio_streams'), {create}=require('./native_radio_server');
const directory=path.join(__dirname,'local-only/radio-fixtures/owner'), cache=path.join(directory,'cache');
function declaration(source,name) {
  const start=source.indexOf('function '+name+'('), brace=source.indexOf('{',start);
  let depth=0, quote=null, escaped=false;
  for(let i=brace;i<source.length;i++) {
    const c=source[i];if(quote){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c===quote)quote=null;continue;}
    if(c==='"'||c==="'"||c==='`'){quote=c;continue;}
    if(c==='{')depth++;else if(c==='}'&&!--depth)return source.slice(start,i+1);
  }throw Error('Missing declaration '+name);
}
async function main() {
  fs.mkdirSync(path.join(directory,'Audio/Config'),{recursive:true});
  fs.mkdirSync(path.join(directory,'Audio/Streams'),{recursive:true});
  const generated=spawnSync('python3',['-c',
    'import sys; sys.path.insert(0,sys.argv[1]); import numpy as np,soundfile as sf; t=np.arange(16000)/32000; sf.write(sys.argv[2],np.column_stack((np.sin(t*1234)*.1,np.sin(t*5678)*.2)),32000,format="OGG",subtype="VORBIS")',
    path.join(__dirname,'local-only/toolchains/python-audio'),path.join(directory,'fixture.ogg')],{encoding:'utf8'});
  assert.equal(generated.status,0,generated.stderr);
  const payload=fs.readFileSync(path.join(directory,'fixture.ogg')), offset=29;
  const pack=Buffer.alloc(offset+streams.HEADER+payload.length);
  for(let i=0;i<payload.length;i++) {const at=offset+streams.HEADER+i;pack[at]=payload[i]^streams.KEY[at&15];}
  fs.writeFileSync(path.join(directory,'Audio/Streams/CH'),pack);
  fs.writeFileSync(path.join(directory,'Audio/Streams/ADVERTS'),pack);
  const names=Buffer.alloc(16*3+3);names.write('CH');names.write('ADVERTS',16);names.write('MISSING',32);
  fs.writeFileSync(path.join(directory,'Audio/Config/STRMPAKS.DAT'),names);
  const lookup=Buffer.alloc(12*7+5);
  const row=(n,p,o,s)=>{lookup[n*12]=p;lookup.writeUInt32LE(o,n*12+4);lookup.writeUInt32LE(s,n*12+8);};
  row(0,0,offset,pack.length-offset);row(1,1,offset,pack.length-offset);
  row(2,2,0,9000);row(3,0,offset,8068);row(4,0,pack.length-2,9000);row(5,250,0,9000);row(6,0,offset,pack.length-offset);
  fs.writeFileSync(path.join(directory,'Audio/Config/TRAKLKUP.DAT'),lookup);
  const source=archivedModules().factories[19737].toString();
  const namesSource=source.slice(source.lastIndexOf('mR=',source.indexOf('function mY'))+3);
  const stations=JSON.parse(namesSource.slice(0,namesSource.indexOf('],mL=')+1).replace(/([{,])([a-zA-Z]+):/g,'$1"$2":'));
  const mW=async(file,start,end)=>new Uint8Array(await file.slice(start,end).arrayBuffer());
  const original=Function('mW','mR','return (async '+declaration(source,'mH')+');')(mW,stations);
  const files=Object.fromEntries([...streams.discover(directory)].map(([name,file])=>[name,new Blob([fs.readFileSync(file)])]));
  const expected=await original(files), actual=streams.catalog(directory);
  assert.deepEqual(actual.stations.map(x=>x.map(t=>t.id)),JSON.parse(JSON.stringify(expected.stations.map(x=>x.map(t=>t.id)))));
  assert.deepEqual(actual.adverts.map(t=>t.id),[1]);
  const originalReader=Function('mW','mq','return ('+declaration(source,'mK')+');')(mW,[...streams.KEY]);
  for(const [start,end]of[[0,100],[1,2],[15,33],[127,5000],[payload.length-10,payload.length+100],[payload.length+1,payload.length+2]]) {
    const reference=await originalReader(expected.stations[1][0]).read(start,end);
    assert.deepEqual(streams.read(actual.stations[1][0],start,end),Buffer.from(reference));
  }
  assert.deepEqual(streams.read(actual.stations[1][0],0,payload.length),payload);
  const configuration=path.join(directory,'owner.json');fs.writeFileSync(configuration,JSON.stringify({directory}));
  const server=create({configuration,cache});
  assert.equal(server.index().stations[1].length,2);
  const [file,duplicate]=await Promise.all([server.converted(actual.stations[1][0]),server.converted(actual.stations[1][0])]);
  assert.equal(file,duplicate);assert.equal(fs.readFileSync(file).toString('ascii',0,4),'RIFF');
  async function request(url,range,method='GET') {
    const chunks=[];let status,headers;
    const response=new Writable({write(chunk,encoding,done){chunks.push(chunk);done();}});
    response.writeHead=(s,h)=>{status=s;headers=h||{};response.headersSent=true;};
    const done=new Promise(resolve=>response.on('finish',resolve));
    assert.equal(await server.handle({method,headers:range?{range}:{}},response,url),true);await done;
    return {status,headers,body:Buffer.concat(chunks)};
  }
  const complete=await request('/game/radio/native/track/0.wav');assert.equal(complete.status,200);
  const partial=await request('/game/radio/native/track/0.wav','bytes=4-31');
  assert.equal(partial.status,206);assert.deepEqual(partial.body,complete.body.subarray(4,32));
  const head=await request('/game/radio/native/track/0.wav',null,'HEAD');assert.equal(head.body.length,0);
  assert.equal(head.headers['content-length'],complete.body.length);
  assert.equal((await request('/game/radio/native/track/0.wav','bytes=9999999-')).status,416);
  assert.equal((await request('/game/radio/native/track/99.wav')).status,404);
  assert.equal((await request('/game/radio/native/track/0.wav',null,'POST')).status,405);
  assert.equal(fs.readdirSync(cache).some(name=>/\.(ogg|partial)$/.test(name)),false);
  const limitedCache=path.join(directory,'limited-cache'),limited=create({configuration,cache:limitedCache,cacheBytes:1});
  await limited.converted(actual.stations[1][0]);
  await limited.converted(actual.adverts[0]);
  assert.equal(fs.readdirSync(limitedCache).filter(name=>name.endsWith('.wav')).length,1,'Generated cache exceeded budget beyond its retained current track');
  console.log('PASS: actual archived pack catalog and XOR ranges match; synthetic Vorbis decodes to native PCM; concurrent cache, HTTP GET/HEAD/ranges/missing/method handling pass');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
