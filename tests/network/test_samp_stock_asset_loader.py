#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual bounded HTTP/local acquisition -> frozen RW decoders -> static CPU plan.

Generated fixtures contain no retail bytes. Owner fixtures remain local-only.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import copy
import gzip
import hashlib
import http.server
import importlib.util
import json
import os
import pathlib
import signal
import socketserver
import struct
import subprocess
import tempfile
import threading
import time
import zlib

ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/stock-asset-loader';OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('generated_stock_assets',ROOT/'tests/artwork_session/fixtures.py')
fixtures=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixtures)
dff,_=fixtures.assets()
p,chunk=fixtures.p,fixtures.chunk

def txd(entries):
    body=chunk(1,p('HH',len(entries),2))
    for name,rgba in entries:
        pixel=bytes([rgba[2],rgba[1],rgba[0],rgba[3]])*4
        fields=p('II32s32sIIHHBBBB',9,0x1101,name.encode(),b'',0x500,21,2,2,32,1,4,1)
        body+=chunk(21,chunk(1,fields+p('I',len(pixel))+pixel)+chunk(3))
    return chunk(22,body+chunk(3))

FILES={'panel.dff':dff,'child.txd':txd([('session_texture',[255,0,0,255])]),
       'parent.txd':txd([('session_texture',[0,0,255,255]),('parent_only',[0,255,0,255])])}
# A generated authored collision box, not collision inferred from render vertices.
col_body=p('10f',2,0,0,0,-1,-1,-1,1,1,1)+p('III',0,0,1)
col_body+=p('6f',-1,-1,-1,1,1,1)+bytes([1,2,3,4])+p('II',0,0)
col=p('4sI22sH',b'COLL',len(col_body)+24,b'panel',1000)+col_body
embedded_dff=chunk(16,dff[12:-12]+chunk(3,chunk(0x253f2fa,col)))
malformed_col=chunk(16,dff[12:-12]+chunk(3,chunk(0x253f2fa,b'COL4'+col[4:])))
ACCESS_TOKEN='a'*64
AUTH_FILES={hashlib.sha256(value).hexdigest()+pathlib.Path(name).suffix:value for name,value in FILES.items()}
REDIRECT_SAME=chunk(16,dff[12:-12]+chunk(3,chunk(0x1201,b'own-same-redirect')))
REDIRECT_CROSS=chunk(16,dff[12:-12]+chunk(3,chunk(0x1201,b'own-cross-redirect')))
AUTH_FILES[hashlib.sha256(REDIRECT_SAME).hexdigest()+'.dff']=REDIRECT_SAME
AUTH_FILES[hashlib.sha256(REDIRECT_CROSS).hexdigest()+'.dff']=REDIRECT_CROSS
cross_events=[]
events=[];event_lock=threading.Lock();active=0;maximum=0

class Server(socketserver.ThreadingMixIn,http.server.HTTPServer):
    daemon_threads=True

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args):pass
    def do_GET(self):
        global active,maximum
        parts=self.path.strip('/').split('/')
        mode,name=parts if len(parts)==2 else ('invalid','none')
        with event_lock:
            events.append({'path':self.path,'cookie':self.headers.get('Cookie'),
                           'authorization':self.headers.get('Authorization'),'encoding':self.headers.get('Accept-Encoding')})
            active+=1;maximum=max(maximum,active)
        try:
            if self.path.startswith('/game/native/stock-img/'):
                if self.headers.get('Cookie')!='zgta_access='+ACCESS_TOKEN:
                    self.send_response(401);self.send_header('Content-Length','0');self.end_headers();return
                data=AUTH_FILES.get(self.path.rsplit('/',1)[-1])
                if data in (REDIRECT_SAME,REDIRECT_CROSS):
                    self.send_response(302)
                    target='/unrelated/redirect.dff' if data==REDIRECT_SAME else f'http://127.0.0.1:{cross_server.server_port}/unrelated/redirect.dff'
                    self.send_header('Location',target);self.send_header('Content-Length','0');self.end_headers();return
                if data is None:self.send_error(404);return
                self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data);return
            if mode=='unrelated':
                self.send_response(401);self.send_header('Content-Length','0');self.end_headers();return
            if mode=='slow':time.sleep(0.3)
            if mode=='timeout':time.sleep(1)
            if mode=='http':self.send_error(404);return
            if mode=='redirect':
                self.send_response(302);self.send_header('Location','/must-not-follow/panel.dff');self.send_header('Content-Length','0');self.end_headers();return
            data=FILES.get(name,col if name=='fixture.col' else b'')
            if mode=='corrupt' and name in ('panel.dff','fixture.col'):data=data[:-1]+bytes([data[-1]^0x80])
            if mode=='bad-dff' and name=='panel.dff':data=b'X'*len(data)
            if mode=='embedded' and name=='panel.dff':data=embedded_dff
            if mode=='bad-col' and name=='panel.dff':data=malformed_col
            if mode=='bad-txd' and name=='child.txd':data=b'Y'*len(data)
            if mode=='unresolved' and name=='child.txd':data=txd([('other_texture',[255,0,0,255])])
            if mode=='unresolved' and name=='parent.txd':data=txd([('parent_only',[0,255,0,255])])
            if mode=='encoding':data=gzip.compress(data)
            self.send_response(200)
            self.send_header('Set-Cookie','should_never_return=secret; Path=/')
            if mode=='encoding':self.send_header('Content-Encoding','gzip')
            chunked=mode in ('oversize','short')
            if chunked:self.send_header('Transfer-Encoding','chunked')
            else:self.send_header('Content-Length',str(len(data)+(100 if mode=='length' else 0)))
            self.end_headers()
            if mode=='oversize':data+=b'over-advertised-size'*3000
            if mode=='short':data=data[:-1]
            for i in range(0,len(data),1024):
                part=data[i:i+1024]
                if chunked:self.wfile.write(f'{len(part):x}\r\n'.encode()+part+b'\r\n')
                else:self.wfile.write(part)
                self.wfile.flush()
            if chunked:self.wfile.write(b'0\r\n\r\n');self.wfile.flush()
        except (BrokenPipeError,ConnectionResetError):pass
        finally:
            with event_lock:active-=1

class CrossHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        cross_events.append({'path':self.path,'cookie':self.headers.get('Cookie')})
        self.send_response(200);self.send_header('Content-Length','0');self.end_headers()
cross_server=Server(('127.0.0.1',0),CrossHandler)
threading.Thread(target=cross_server.serve_forever,daemon=True).start()
server=Server(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
base=f'http://127.0.0.1:{server.server_port}'

def asset(data,path):return {'path':path,'bytes':len(data),'crc32':zlib.crc32(data),'sha256':hashlib.sha256(data).hexdigest()}
def manifest(mode='valid',kind='object',files=None):
    data=FILES if files is None else files
    return {'schema':1,'models':[{'id':1000,'kind':kind,'model':'panel','txd':'child','source':'data/generated.ide','line':1}],
            'parents':{'child':'parent'},'vehicleDictionary':'vehicle','vehicleGenericFirst':True,
            'assets':{name:asset(value,f'{mode}/{name}') for name,value in data.items()}}

try:
    with tempfile.TemporaryDirectory(dir=OUT,prefix='generated-') as tmp:
        work=pathlib.Path(tmp);cases=[]
        def case(label,expected='ok',mode='valid',modify=None,local=False,**options):
            value=manifest(mode)
            if modify:modify(value)
            path=work/(label+'.json');path.write_text(json.dumps(value))
            row={'label':label,'expect':expected,'manifest':str(path),'base':base,'id':1000,**options}
            if local:
                for name,data in FILES.items():
                    target=work/'local'/mode/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
                row.update(base=(work/'local').as_uri()+'/',local=True)
            cases.append(row)
            return value,path
        case('http-valid-parent-priority')
        case('local-valid-parent-priority',local=True)
        case('crc-failure','crc',mode='corrupt')
        case('sha-failure','sha',modify=lambda m:m['assets']['panel.dff'].update(sha256='0'*64))
        case('advertised-CRC-failure','crc',modify=lambda m:m['assets']['panel.dff'].update(crc32=1))
        case('response-length','size',mode='length')
        case('chunked-overrun','size',mode='oversize')
        case('chunked-short','size',mode='short')
        case('HTTP-status','http',mode='http')
        case('redirect-rejected','redirect',mode='redirect')
        case('compressed-body-rejected','encoding',mode='encoding')
        case('wrong-origin','url',mutation='origin')
        case('forged-path','resolution',mutation='path')
        case('missing-dff','missing',modify=lambda m:m['assets'].pop('panel.dff'))
        case('missing-parent','missing',modify=lambda m:m['assets'].pop('parent.txd'))
        for kind in ('ped','vehicle','animated','hierarchy'):
            case('unsupported-'+kind,'kind',modify=lambda m,k=kind:m['models'][0].update(kind=k))
        case('file-budget','limit',limits={'file':20})
        case('encoded-budget','limit',limits={'encoded':30})
        case('chain-file-budget','limit',limits={'files':2})
        case('decoded-texture-budget','txd',limits={'decoded':20})
        case('decoded-count-budget','txd',limits={'textures':2})
        case('prepared-budget','plan',limits={'prepared':12})
        case('embedded-authored-COL','ok',mode='embedded',modify=lambda m:m['assets'].update({'panel.dff':asset(embedded_dff,'embedded/panel.dff')}))
        case('malformed-authored-COL','col',mode='bad-col',modify=lambda m:m['assets'].update({'panel.dff':asset(malformed_col,'bad-col/panel.dff')}))
        case('response-timeout','timeout',mode='timeout',limits={'timeout':0.15})
        bad_dff={'panel.dff':b'X'*len(dff),**{k:v for k,v in FILES.items() if k!='panel.dff'}}
        case('malformed-native-dff','dff',mode='bad-dff',modify=lambda m:m['assets'].update({'panel.dff':asset(bad_dff['panel.dff'],'bad-dff/panel.dff')}))
        case('malformed-native-txd','txd',mode='bad-txd',modify=lambda m:m['assets'].update({'child.txd':asset(b'Y'*len(FILES['child.txd']),'bad-txd/child.txd')}))
        def unresolved(m):
            m['assets']['child.txd']=asset(txd([('other_texture',[255,0,0,255])]),'unresolved/child.txd')
            m['assets']['parent.txd']=asset(txd([('parent_only',[0,255,0,255])]),'unresolved/parent.txd')
        case('missing-material-no-placeholder','textures',mode='unresolved',modify=unresolved)
        # Same manifest file URL requires explicit local opt-in.
        _,localpath=case('local-forbidden','url',local=True)
        cases[-1]['local']=False
        _,symlink_manifest=case('local-symlink-escape','url',local=True,mode='symlink')
        outside=work/'outside.dff';outside.write_bytes(dff)
        link=work/'local/symlink/panel.dff';link.unlink();link.symlink_to(outside)
        owner=ROOT.parent/'ZGTA-SA-core-102/local-only/research/stock-models/extracted-eight'
        for model in (966,980,1225,1231):
            cases.append({'label':f'owner-exact-{model}','expect':'ok','manifest':str(owner/'catalog.json'),
                          'base':(owner/'overlay').as_uri()+'/','id':model,'local':True})
        def authenticated_assets(m):
            for name,value in FILES.items():m['assets'][name]=asset(value,'game/native/stock-img/'+hashlib.sha256(value).hexdigest()+pathlib.Path(name).suffix)
        case('gated-stock-default-no-cookie','http',modify=authenticated_assets)
        case('gated-stock-explicit-own-access','ok',modify=authenticated_assets,access='valid')
        case('gated-stock-expired-access','http',modify=authenticated_assets,access='expired')
        case('gated-stock-Secure-over-HTTP','http',modify=authenticated_assets,access='secure')
        case('gated-stock-wrong-origin','http',modify=authenticated_assets,access='wrong-origin')
        def redirect_assets(m,data):
            authenticated_assets(m)
            m['assets']['panel.dff']=asset(data,'game/native/stock-img/'+hashlib.sha256(data).hexdigest()+'.dff')
        case('gated-stock-same-origin-redirect','redirect',modify=lambda m:redirect_assets(m,REDIRECT_SAME),access='valid')
        case('gated-stock-cross-origin-redirect','redirect',modify=lambda m:redirect_assets(m,REDIRECT_CROSS),access='valid')
        case('unrelated-path-no-access-cookie','http',mode='unrelated',access='valid')
        special=work/'special.json';special.write_text(json.dumps(manifest('slow')))
        config=work/'cases.json';config.write_text(json.dumps(cases))
        raw_cases=[{'label':'raw-http-COL','base':base,'expect':'ok','metadata':asset(col,'raw/fixture.col')},
                   {'label':'raw-COL-corruption','base':base,'expect':'crc','metadata':asset(col,'corrupt/fixture.col')},
                   {'label':'raw-COL-SHA','base':base,'expect':'sha','metadata':{**asset(col,'raw/fixture.col'),'sha256':'0'*64}},
                   {'label':'raw-COL-stream-overrun','base':base,'expect':'size','metadata':asset(col,'oversize/fixture.col')}]
        collision=ROOT/'local-only/research/stock-collision/overlay'
        for model in (966,980,1225,1231):
            raw_cases.append({'label':f'raw-owner-COL-{model}','base':collision.as_uri()+'/',
                              'expect':'ok','catalog':str(collision/'game/native/stock-collision/catalog.json'),'id':model,'local':True})
        raw_config=work/'raw-cases.json';raw_config.write_text(json.dumps(raw_cases))
        sources=['NativeSAMPStockModels.swift','NativeRenderWareDFF.swift','NativeRenderWareTXD.swift',
                 'NativeRenderWareModel.swift','NativeRenderWareCollision.swift','NativeSAMPStockCollisionCatalog.swift','NativeStockAssetAccess.swift','NativeSAMPStockAssetLoader.swift']
        binary=OUT/'stock-asset-loader-tests'
        command=['xcrun','swiftc','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',
                 *[str(ROOT/'ios/App'/s) for s in sources],str(ROOT/'tests/stock_asset_loader/main.swift'),'-o',str(binary)]
        with (OUT/'build.log').open('w') as log:
            built=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,text=True,start_new_session=True)
            try:code=built.wait(timeout=240)
            except subprocess.TimeoutExpired:
                os.killpg(built.pid,signal.SIGKILL);built.wait();raise
        if code:raise RuntimeError((OUT/'build.log').read_text())
        run=subprocess.run([str(binary),str(config),str(special),base,str(raw_config)],capture_output=True,text=True,timeout=120)
        (OUT/'stdout.log').write_text(run.stdout);(OUT/'stderr.log').write_text(run.stderr)
        if run.returncode:raise RuntimeError(f'Native tests {run.returncode}\n{run.stdout}\n{run.stderr}')
        report=json.loads(run.stdout)
        stock_events=[e for e in events if e['path'].startswith('/game/native/stock-img/')]
        default_events=[e for e in events if not e['path'].startswith('/game/native/stock-img/')]
        assert all(e['cookie'] is None for e in default_events)
        assert all(e['cookie'] in (None,'zgta_access='+ACCESS_TOKEN) for e in stock_events)
        assert any(e['cookie']=='zgta_access='+ACCESS_TOKEN for e in stock_events)
        assert all(e['authorization'] is None and e['encoding']=='identity' for e in events)
        assert cross_events==[]
        assert not any(e['path']=='/unrelated/redirect.dff' for e in events)
        assert not any(e['path'].startswith('/must-not-follow/') for e in events)
        report.update(httpRequests=len(events),defaultCookieFree=True,authorizationFree=True,optInStockCookieOnly=True,redirectFollowed=False,
                      ownerCases=4,ownerExternalCOLCases=4,sourceSHA256={s:hashlib.sha256((ROOT/'ios/App'/s).read_bytes()).hexdigest() for s in sources})
        (OUT/'requests.json').write_text(json.dumps(events,indent=2)+'\n')
        (OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
        print(json.dumps(report,indent=2,sort_keys=True))
finally:server.shutdown();server.server_close();cross_server.shutdown();cross_server.server_close()
