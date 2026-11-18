#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Real serve_local stock routes in isolated source/state fixtures, never8801."""
import hashlib
import http.client
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import time
import zlib
import prepare_native_stock_img as img

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/stock-native-server';OUT.mkdir(parents=True,exist_ok=True)
DEPENDENCIES=['serve_local.js','browser_recovery_hook.js','browser_recovery.js','stock_native_assets.js','stock_img_assets.js','selfhost_backend.js','native_resource_server.js',
              'optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js', 'player_placement.js',
              'local_gameplay.js','native_radio_server.js','radio_streams.js','prepare_native_radio_audio.py']
events=[];checks=0
def check(value,label):
    global checks
    checks+=1
    if not value:raise AssertionError(label)

def request(port,path,method='GET',headers=None,body=None,limit=16*1024*1024):
    connection=http.client.HTTPConnection('127.0.0.1',port,timeout=20)
    try:
        connection.request(method,path,body=body,headers=headers or {})
        response=connection.getresponse();data=response.read(limit+1)
        if len(data)>limit:raise AssertionError('HTTP fixture response exceeded client bound')
        events.append({'method':method,'path':path,'status':response.status,'bytes':len(data)})
        return response.status,dict(response.getheaders()),data
    finally:connection.close()

def free_port():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0));number=listener.getsockname()[1]
        assert number!=8801
        return number

def files(root):
    for name in DEPENDENCIES:shutil.copyfile(ROOT/name,root/name)
    local=root/'local-only';site=local/'site';(site/'game/world').mkdir(parents=True)
    (site/'game/world/index.json').write_text('{"water":[],"tiles":[]}')
    (site/'game/world/collision.json').write_text('{"cells":[]}')
    (local/'selfhost').mkdir();(local/'selfhost/client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
    # These must never fall through to archived-site serving.
    for name in ['stock-models.json','stock-collision/catalog.json','stock-collision/index.json',
                 'stock-img/'+('0'*64)+'.dff','stock-collision/'+('0'*64)+'.col']:
        p=site/'game/native'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('FORBIDDEN ARCHIVE FALLBACK')
    (root/'no-network.js').write_text("const h=require('node:https');h.request=h.get=()=>{require('node:fs').writeFileSync('unexpected-upstream','1');throw Error('No network permitted in stock route regression')};\n")
    return local

def start(root,config=None,selfhost=True,env_extra=None):
    number=free_port();env=dict(os.environ)
    for key in list(env):
        if key.startswith('ZGTA_'):env.pop(key)
    env.update(PORT=str(number),ZGTA_SELFHOST='1' if selfhost else '0',BIND_HOST='127.0.0.1',
               ZGTA_ALLOWED_HOSTS='lan.example',ZGTA_JOIN_CODE='fixture-join-code-123456' if selfhost else '')
    if config is not None:
        file=root/'local-only/stock-native-assets.json';file.write_text(json.dumps(config));env['ZGTA_STOCK_NATIVE_CONFIG']=str(file)
    env.update(env_extra or {})
    output=(root/'server.log').open('w')
    process=subprocess.Popen(['node','-r','./no-network.js','serve_local.js'],cwd=root,env=env,stdout=output,stderr=subprocess.STDOUT)
    for _ in range(100):
        if process.poll() is not None:raise AssertionError((root/'server.log').read_text())
        try:
            code=request(number,'/api/local/status' if selfhost else '/game/native/stock-models.json')[0]
            if code==(200 if selfhost else 404):return number,process,output
        except OSError:pass
        time.sleep(.05)
    process.terminate();process.wait(timeout=5);raise AssertionError('isolated stock HTTP server did not start')

def stop(item):
    _,process,output=item;process.terminate()
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:process.kill();process.wait()
    output.close()

def authenticate(port):
    code,headers,_=request(port,'/api/local/join','POST',{'Host':'lan.example','Content-Type':'application/json'},json.dumps({'code':'fixture-join-code-123456'}))
    check(code==200,'join gate grants fixture cookie')
    return {'Host':'lan.example','Cookie':headers['Set-Cookie'].split(';')[0]}

def verify(data,asset):
    check(len(data)==asset['bytes'],'advertised resource bytes')
    check(zlib.crc32(data)==asset['crc32'],'advertised resource CRC32')
    check(hashlib.sha256(data).hexdigest()==asset['sha256'],'advertised resource SHA256')

link=ROOT/'local-only/selfhost';link_before=os.readlink(link) if link.is_symlink() else None
with tempfile.TemporaryDirectory(dir=OUT,prefix='isolated-') as temporary:
    work=Path(temporary)
    clean=work/'clean';clean.mkdir();files(clean)
    run=start(clean,selfhost=False)
    try:
        for route in ['/game/native/stock-models.json','/game/native/stock-collision/index.json','/game/native/stock-collision/catalog.json',
                      '/game/native/stock-img/'+('0'*64)+'.dff','/game/native/stock-collision/'+('0'*64)+'.col']:
            code,_,body=request(run[0],route)
            check(code==404 and b'FORBIDDEN' not in body,'clean checkout explicit404, never archive/upstream')
        check(not (clean/'unexpected-upstream').exists(),'stock clean checkout performed no upstream call')
    finally:stop(run)

    # Synthetic authored COL used for destructive corruption/bounds cases.
    generated=work/'generated';generated.mkdir();local=files(generated)
    body=struct.pack('<10fIII6f4BII',2,0,0,0,-1,-1,-1,1,1,1,0,0,1,-1,-1,-1,1,1,1,1,2,3,4,0,0)
    col=struct.pack('<4sI22sH',b'COLL',len(body)+24,b'panel',1000)+body
    digest=hashlib.sha256(col).hexdigest();relative='game/native/stock-collision/'+digest+'.col'
    overlay=local/'collision';target=overlay/relative;target.parent.mkdir(parents=True);target.write_bytes(col)
    record={'path':relative,'bytes':len(col),'crc32':zlib.crc32(col),'sha256':digest,'version':1,'headerName':'panel','headerModelID':1000,'sources':[]}
    catalog={'schema':2,'models':[{'name':'panel','bindings':[],'records':[record]}]}
    catalog_path=target.parent/'catalog.json';catalog_path.write_text(json.dumps(catalog))
    run=start(generated,{'collisionRoot':str(overlay)})
    try:
        number=run[0];headers=authenticate(number)
        code,_,data=request(number,'/'+relative,headers=headers);check(code==200,'generated COL actual route');verify(data,record)
        target.write_bytes(col[:-1]+bytes([col[-1]^1]));check(request(number,'/'+relative,headers=headers)[0]==503,'COL corruption never served')
        target.write_bytes(col[:-1]);check(request(number,'/'+relative,headers=headers)[0]==503,'COL truncation never served')
        with target.open('wb') as stream:stream.truncate(32*1024*1024+1)
        check(request(number,'/'+relative,headers=headers)[0]==503,'oversized COL rejected before unbounded read')
        target.unlink();outside=local/'outside.col';outside.write_bytes(col);target.symlink_to(outside)
        check(request(number,'/'+relative,headers=headers)[0]==503,'COL symlink escape blocked')
        target.unlink();target.write_bytes(col)
        check(request(number,'/'+relative,headers=headers)[0]==200,'restored exact COL can serve')
    finally:stop(run)

    # Metadata and configuration limits use only generated private sparse files.
    with catalog_path.open('wb') as stream:stream.truncate(16*1024*1024+1)
    run=start(generated,{'collisionRoot':str(overlay)})
    try:check(request(run[0],'/game/native/stock-collision/catalog.json',headers=authenticate(run[0]))[0]==503,'oversized metadata bounded')
    finally:stop(run)
    run=start(generated,{'imgIndex':'missing-index.json'})
    try:
        check(request(run[0],'/game/native/stock-models.json',headers={'Host':'lan.example'})[0]==401,'join gate precedes invalid local config')
        check(request(run[0],'/game/native/stock-models.json',headers=authenticate(run[0]))[0]==503,'incomplete config explicit error')
    finally:stop(run)

    # Actual complete metadata/IMG/COL paths are read-only; test state is isolated.
    owner=work/'owner';owner.mkdir();files(owner)
    source=ROOT.parent/'ZGTA-SA-core-102/local-only/research/stock-models'
    config={'imgIndex':str(ROOT/'local-only/research/stock-img/index.json'),
            'stockManifest':str(ROOT/'local-only/research/stock-img/stock-models.json'),
            'archivePaths':{name:str(source/'retail-img/models'/name) for name in ['gta3.img','gta_int.img']},
            'collisionRoot':str(ROOT/'local-only/research/stock-collision-full/overlay')}
    run=start(owner,config)
    owner_resources=0
    try:
        number=run[0]
        check(request(number,'/game/native/stock-models.json',headers={'Host':'unlisted.example'})[0]==421,'Host guard first')
        check(request(number,'/game/native/stock-models.json',headers={'Host':'lan.example','Origin':'https://other.example'})[0]==403,'Origin guard first')
        check(request(number,'/game/native/stock-models.json',headers={'Host':'lan.example'})[0]==401,'join required before stock metadata')
        check(request(number,'/game/native/stock-models.json',headers={'X-Forwarded-For':'192.0.2.4'})[0]==401,'loopback reverse proxy cannot bypass join')
        headers=authenticate(number)
        code,meta,data=request(number,'/game/native/stock-models.json',headers=headers)
        check(code==200 and meta['Cross-Origin-Embedder-Policy']=='require-corp','stock metadata preserves server security headers')
        stock=json.loads(data);check(len(stock['models'])==14832,'full stock catalog served')
        models={row['id']:row for row in stock['models']}
        code,_,data=request(number,'/game/native/stock-collision/catalog.json',headers=headers)
        check(code==200,'actual runtime COL catalog URL')
        collision=json.loads(data);check(collision['schema']==2 and collision['coverage']['complete'],'complete COL coverage served')
        code,_,alias=request(number,'/game/native/stock-collision/index.json',headers=headers)
        check(code==200 and alias==data,'index alias preserves runtime catalog bytes')
        by_name={row['name']:row for row in collision['models']}
        old=json.loads((source/'extracted-eight/extraction-report.json').read_text())
        expected={row['name']:row for row in old['files']}
        for model_id in [966,980,1225,1231]:
            model=models[model_id]
            for name in [model['model']+'.dff',model['txd']+'.txd']:
                asset=stock['assets'][name];code,_,body=request(number,'/'+asset['path'],headers=headers)
                check(code==200,'owned exact DFF/TXD HTTP route');verify(body,asset)
                check(hashlib.sha256(body).hexdigest()==expected[name]['logicalSHA256'],'independent earlier extraction digest')
                owner_resources+=1
            row=by_name[model['model']];check(any(binding['id']==model_id for binding in row['bindings']),'exact COL IDE binding')
            check(len(row['records'])==1,'unique exact COL record')
            record=row['records'][0];code,_,body=request(number,'/'+record['path'],headers=headers)
            check(code==200,'owned exact COL HTTP route');verify(body,record);owner_resources+=1
            check(struct.unpack_from('<H',body,30)[0]==record['headerModelID'],'raw COL header hint preserved')
        asset=stock['assets'][models[966]['model']+'.dff'];route='/'+asset['path']
        code,head,body=request(number,route,'HEAD',headers=headers)
        check(code==200 and not body and int(head['Content-Length'])==asset['bytes'],'HEAD exact bytes without body')
        check(request(number,route,'POST',headers=headers)[0]==405,'stock method restricted')
        check(request(number,route,headers={**headers,'Range':'bytes=0-1'})[0]==416,'partial stock file rejected')
        for bad in [route+'?alias=1','/game/native/stock-img/%2e%2e/%2e%2e/players.json',
                    '/%67ame/native/stock-collision/'+('0'*64)+'.col',
                    '/game/native/stock-collision/../../players.json','/game/native/stock-collision/'+('0'*64)+'.col']:
            check(request(number,bad,headers=headers)[0]==404,'stock traversal/unknown alias never falls through')
        check(not (owner/'unexpected-upstream').exists(),'actual stock routes did not proxy upstream')
    finally:stop(run)
    shutil.copyfile(owner/'server.log',OUT/'owner-server.log')

check((os.readlink(link) if link.is_symlink() else None)==link_before,'Core103 selfhost symlink unchanged')
report={'status':'PASS','checks':checks,'ownedHTTPResources':owner_resources,'existingServer8801Touched':False,
        'selfhostState':'All HTTP servers used private copied-source fixtures and independent saves.',
        'scope':'Actual serve_local Host/Origin/join checks and bounded stock HTTP routes; native GPU/physics registration is separate.',
        'sourceSHA256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ['serve_local.js','stock_native_assets.js','stock_img_assets.js','test_stock_native_server.py','smoke_host.py']}}
(OUT/'requests.json').write_text(json.dumps(events,indent=2)+'\n');(OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(report,indent=2,sort_keys=True))
