#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual extracted Renderer stock callbacks + verified HTTP, Metal and Rapier.

Uses a narrow renderer carrier; external attachment parents, UIKit, display-link
scheduling and a SA-MP server are outside this gate. Original resources stay local.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import copy
import gzip
import hashlib
import http.server
import importlib.util
import json
import platform
import socketserver
import struct
import subprocess
import threading
import time
import zlib

from tests.movement.smoke_native_climb_runtime import function
from tests.resources.smoke_native_renderware_collision import fixture

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/stock-runtime';OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('stock_runtime_own_fixtures',ROOT/'tests/artwork_session/fixtures.py')
own=importlib.util.module_from_spec(spec);spec.loader.exec_module(own)
dff,txd=own.assets()
files={};events=[];event_lock=threading.Lock();slow_paths=set();gate_enabled=False
ACCESS_TOKEN='a'*64
def asset(data,path):
    files['/'+path]=data
    return dict(path=path,bytes=len(data),crc32=zlib.crc32(data)&0xffffffff,sha256=hashlib.sha256(data).hexdigest())
def raw_col(name,model_id=0,empty=False):
    if empty:
        body=struct.pack('<10f',-1,-1,-1,1,1,1,0,0,0,2)+bytes(48)
        return struct.pack('<4sI22sH',b'COL3',len(body)+24,name.encode(),model_id)+body
    raw=fixture(3)
    return raw[:8]+name.encode().ljust(22,b'\0')+struct.pack('<H',model_id)+raw[32:]

source_hash=hashlib.sha256(b'own generated IDE definitions for stock runtime regressions').hexdigest()
models=[];assets={};collision=[]
for i,name in [(1000,'panel'),(1001,'no_col'),(1002,'incomplete'),(1003,'bad_col'),(1004,'slow'),(1005,'empty_col')]:
    for ext,data in [('dff',dff),('txd',txd)]:
        if name=='slow'and ext=='dff':data=data[:8]+struct.pack('<I',int.from_bytes(data[8:12],'little')^1)+data[12:]
        path='game/native/stock-img/'+hashlib.sha256(data).hexdigest()+'.'+ext
        assets[name+'.'+ext]=asset(data,path)
        if name=='slow'and ext=='dff':slow_paths.add('/'+path)
    models.append(dict(id=i,kind='object',model=name,txd=name,source='data/maps/own.ide',line=i))
    records=[]
    if name not in ('no_col','incomplete'):
        raw=raw_col(name,empty=name=='empty_col');digest=hashlib.sha256(raw).hexdigest()
        meta=asset(raw,'game/native/stock-collision/'+digest+'.col')
        records=[{**meta,'version':3,'headerModelID':0,'headerName':name,
                  'sources':[dict(archive='own.img',collection='own.col',collectionOffset=2048,recordOffset=0)]}]
        if name=='bad_col':files['/'+meta['path']]=raw[:-1]+bytes([raw[-1]^1])
    if name!='incomplete':
        collision.append(dict(name=name,bindings=[dict(id=i,source='data/maps/own.ide',line=i,sourceSHA256=source_hash)],records=records))

owner_manifest=json.loads((ROOT/'local-only/research/stock-img/stock-models.json').read_text())
owner_collision=json.loads((ROOT/'local-only/research/stock-collision-full/overlay/game/native/stock-collision/catalog.json').read_text())
private_assets=ROOT.parent/'ZGTA-SA-core-102/local-only/research/stock-models/extracted-eight/overlay/game/native/stock-assets'
owner_ids=[966,980,1225,1231]
owner_hashes={}
for i in owner_ids:
    row=next(x for x in owner_manifest['models']if x['id']==i);models.append(row)
    for name,ext in [(row['model'],'dff'),(row['txd'],'txd')]:
        p=private_assets/(name+'.'+ext)
        if not p.exists():
            matches=list(private_assets.rglob(name+'.'+ext));assert len(matches)==1,(name,ext);p=matches[0]
        data=p.read_bytes();owner_hashes[str(p)]=hashlib.sha256(data).hexdigest()
        assets[name+'.'+ext]=asset(data,'game/native/stock-img/'+hashlib.sha256(data).hexdigest()+'.'+ext)
    colrow=next(x for x in owner_collision['models']if x['name']==row['model'])
    collision.append(colrow)
    for record in colrow['records']:
        p=ROOT/'local-only/research/stock-collision-full/overlay'/record['path'];data=p.read_bytes()
        owner_hashes[str(p)]=hashlib.sha256(data).hexdigest();files['/'+record['path']]=data
manifest=dict(schema=1,models=models,parents={},assets=assets,vehicleDictionary='vehicle',vehicleGenericFirst=True)
manifest_bytes=json.dumps(manifest,separators=(',',':')).encode()
coverage=dict(complete=True,scope='stock-manifest-img-and-active-colfile',stockManifestSHA256=hashlib.sha256(manifest_bytes).hexdigest(),archiveCount=1,explicitCOLFiles=[])
files['/game/native/stock-models.json']=manifest_bytes
files['/game/native/stock-collision/catalog.json']=json.dumps(dict(schema=2,models=collision,coverage=coverage)).encode()

class Server(socketserver.ThreadingMixIn,http.server.HTTPServer):daemon_threads=True
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args):pass
    def do_GET(self):
        global gate_enabled
        cookie=self.headers.get('Cookie')
        event=dict(path=self.path,cookie=None if cookie is None else '<redacted>',
                   cookieNames=[]if cookie is None else sorted(v.strip().split('=',1)[0]for v in cookie.split(';')),
                   authorization=self.headers.get('Authorization'),encoding=self.headers.get('Accept-Encoding'),gated=gate_enabled)
        with event_lock:events.append(event)
        if self.path=='/control/gate':
            gate_enabled=True;self.send_response(200);self.send_header('Content-Length','0');self.end_headers();return
        if gate_enabled and self.path.startswith('/game/native/') and cookie!='zgta_access='+ACCESS_TOKEN:
            event['denied']=True;self.send_error(401);return
        if self.path in slow_paths:time.sleep(.35)
        if self.path=='/metadata/redirect':
            self.send_response(302);self.send_header('Location','/metadata/must-not-follow');self.send_header('Content-Length','0');self.end_headers();return
        if self.path=='/metadata/http':self.send_error(404);return
        if self.path=='/metadata/slow':time.sleep(.35)
        data=files.get(self.path,b'0123456789abcdef'if self.path.startswith('/metadata/')else None)
        if data is None:self.send_error(404);return
        if self.path=='/metadata/length':data=b'Z'*80
        if self.path=='/metadata/encoding':data=gzip.compress(data)
        try:
            self.send_response(200);self.send_header('Set-Cookie','stock_test=must_not_return; Path=/')
            if self.path=='/metadata/encoding':self.send_header('Content-Encoding','gzip')
            if self.path=='/metadata/chunked':
                self.send_header('Transfer-Encoding','chunked');self.end_headers();data=b'Z'*80
                self.wfile.write(f'{len(data):x}\r\n'.encode()+data+b'\r\n0\r\n\r\n');self.wfile.flush();return
            self.send_header('Content-Length',str(len(data)));self.end_headers()
            self.wfile.write(data);self.wfile.flush()
        except(BrokenPipeError,ConnectionResetError):pass

renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
markers=['private enum LegacyStockMetadata','func receiveLegacyObject(','private func loadLegacyStockCatalogs(',
         'private func legacyStockAccess(',
         'private func refreshLegacyStockReferences(','private func pumpLegacyStockObjects(','private func failLegacyStockObject(',
         'private func legacyCollisionResourceBytes(','private func reserveLegacyModelBytes(','private func installLegacyStockObject(',
         'private func legacyModelApplies(','private func legacyStockObjectReady(','func legacyStockCollisionProvenance(',
         'private func removeLegacyObjectCollision(','private func synchronizeLegacyObjectPhysics(','func invalidateLegacyImports(',
         'private func resolvedLegacyMaterial(','private func loadLegacyDictionary(','private func drawLegacyObjects(']
methods='\n'.join(function(renderer,m).replace('private ','')for m in markers)
prefixes=['private var legacyStock','private enum LegacyStockCollisionKind','private var legacyModelPipelines:',
          'private var legacyModels:','private var legacyModelDefinitions:','private var legacyModelCosts:',
          'private var legacyModelBytes=','private var legacyAssetEpoch:','private let legacyImportQueue=',
          'private var legacyMissingObjects=','private var legacyMaterialOwner:','private var legacyExactTextures:',
          'private var legacyTexture','private var legacyExternalTextureBytes:','private var legacyMaterialErrors=',
          'private var legacyCollision','private lazy var legacyCollisionWorld=','let legacyObjects=', 'var legacyVirtualWorld:']
properties='\n'.join(line.strip().replace('private ','')for line in renderer.splitlines()if any(line.strip().startswith(p)for p in prefixes))
transfer=function(renderer,'private final class LegacyStockMetadataTransfer:').replace('private final class','final class')
carrier=(ROOT/'tests/stock_runtime/main.swift').read_text().replace('// ACTUAL_PROPERTIES',properties).replace('// ACTUAL_METHODS',methods).replace('// ACTUAL_METADATA_TRANSFER',transfer)
source=OUT/'main.swift';source.write_text(carrier)
names=['ServerAddress.swift','NativeSAMPStockModels.swift','NativeSAMPStockCollisionCatalog.swift','NativeSAMPStockAssetLoader.swift',
       'NativeStockAssetAccess.swift',
       'NativeRenderWareDFF.swift','NativeRenderWareTXD.swift','NativeRenderWareModel.swift','NativeRenderWareCollision.swift',
       'NativeRenderWareCollisionWorld.swift','SwiftRapierWorld.swift','NativeSAMPArtwork.swift','NativeSAMPObjects.swift',
       'NativeSAMPProtocol.swift','NativeSAMPTextCodec.swift','NativeSAMPObjectScene.swift','NativeSAMPObjectMaterials.swift']
hashes={n:hashlib.sha256((ROOT/'ios/App'/n).read_bytes()).hexdigest()for n in names+['NativeWorldRenderer.swift']}
library=ROOT/'local-only/native-physics'/('macos-arm64'if platform.machine()=='arm64'else'macos-x86_64')
subprocess.run(['python3',str(ROOT/'native-physics/source_stamp.py'),'check',str(library)],check=True)
binary=OUT/'stock-runtime-tests'
cmd=['xcrun','swiftc','-Onone','-module-cache-path',str(OUT/'host-modules'),'-I',str(ROOT/'native-physics/include'),
     *[str(ROOT/'ios/App'/n)for n in names],str(source),'-L',str(library),'-lzgtasa_native_physics',
     '-framework','Security','-framework','CoreFoundation','-o',str(binary)]
fingerprint=hashlib.sha256(json.dumps({'sources':hashes,'carrier':hashlib.sha256(carrier.encode()).hexdigest(),
    'nativeLibrary':hashlib.sha256((library/'libzgtasa_native_physics.a').read_bytes()).hexdigest(),'command':cmd},sort_keys=True).encode()).hexdigest()
build_info=OUT/'build-info.json'
cached=json.loads(build_info.read_text())if build_info.exists()else{}
if not(binary.exists()and cached.get('fingerprint')==fingerprint and cached.get('binarySHA256')==hashlib.sha256(binary.read_bytes()).hexdigest()):
    with(OUT/'build.log').open('w')as log:build=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
    assert build.returncode==0,(OUT/'build.log').read_text()
    build_info.write_text(json.dumps({'fingerprint':fingerprint,'binarySHA256':hashlib.sha256(binary.read_bytes()).hexdigest()},indent=2)+'\n')
server=Server(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    run=subprocess.run([str(binary),f'http://127.0.0.1:{server.server_port}',str(ROOT/'ios/App/NativeRenderWareModel.metal'),str(OUT)],capture_output=True,text=True,timeout=180)
    (OUT/'stdout.log').write_text(run.stdout);(OUT/'stderr.log').write_text(run.stderr)
    assert run.returncode==0,(run.returncode,run.stdout,run.stderr)
    report=json.loads((OUT/'report.json').read_text())
    for path,digest in owner_hashes.items():assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,path
    for name,digest in hashes.items():assert hashlib.sha256((ROOT/'ios/App'/name).read_bytes()).hexdigest()==digest,name
    assert all(row['cookie']is None for row in events if not row['gated'])
    assert all(row['authorization']is None for row in events)
    assert all(row['encoding']=='identity' for row in events if row['path'].startswith(('/metadata/','/game/native/')))
    gated=[row for row in events if row['gated']and row['path'].startswith('/game/native/')]
    assert any(row.get('denied')for row in gated),'Actual HTTP gate did not reject missing access'
    accepted=[row for row in gated if not row.get('denied')]
    assert accepted and all(row['cookieNames']==['zgta_access']for row in accepted)
    assert not any('must-not-follow'in row['path']for row in events)
    report.update(httpRequests=len(events),credentialFreeBaseline=True,gatedHTTPRequests=len(gated),onlyFirstPartyAccessCookie=True,
                  noAuthorizationOrIdentityCookies=True,redirectFollowed=False,sourceAndOwnerUnchanged=True,sourceSHA256=hashes)
    (OUT/'requests.json').write_text(json.dumps(events,indent=2)+'\n');(OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))
finally:
    (OUT/'requests-last-attempt.json').write_text(json.dumps(events,indent=2)+'\n')
    server.shutdown();server.server_close()
