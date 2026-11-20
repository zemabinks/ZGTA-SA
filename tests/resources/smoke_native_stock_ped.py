#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored stock-ped HTTP/files, actual RW rig/material preparation and upload.

CPU preparation and optional Metal byte readback do not establish gameplay or
renderer registration. Original references, if requested, stay owner-local.
"""
from pathlib import Path
import argparse,hashlib,http.server,json,os,re,socketserver,struct,subprocess,sys,threading,time,zlib
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tests.resources.smoke_native_renderware_skeleton import fixture,chunk,pack,fields
from tests.artwork_session.fixtures import assets as static_assets
def children(data):
    at=0;rows=[]
    while at<len(data):
        kind,n,version=struct.unpack_from('<III',data,at);end=at+12+n
        assert end<=len(data);rows.append((kind,data[at+12:end]));at=end
    return rows
def textured_ped(name='session_texture'):
    root=children(fixture())[0][1];parts=children(root);out=[]
    for kind,body in parts:
        if kind!=26:out.append(chunk(kind,body));continue
        gs=[]
        for k,b in children(body):
            if k!=15:gs.append(chunk(k,b));continue
            geom=[]
            for t,v in children(b):
                if t==1:
                    flags,uv,pad,faces,vertices,morph=struct.unpack_from('<HBBIII',v)
                    v=pack('HBBIII',flags|4,1,pad,faces,vertices,morph)+b''.join(pack('2f',x,y)for x,y in [(0,0),(1,0),(0,1),(1,1)])+v[16:]
                elif t==8:
                    texture=chunk(6,chunk(1,pack('I',0x1106))+chunk(2,name.encode()+b'\0')+chunk(2,b'\0')+chunk(3))
                    mat=chunk(7,chunk(1,pack('I4BII3f',0,255,255,255,255,0,1,1,1,1))+texture+chunk(3))
                    v=chunk(1,pack('Iii',2,-1,0))+mat
                geom.append(chunk(t,v))
            gs.append(chunk(k,b''.join(geom)))
        out.append(chunk(kind,b''.join(gs)))
    return chunk(16,b''.join(out))
def txd(colors):
    fields=pack('II32s32sIIHHBBBB',9,0x1106,b'session_texture',b'',0x8500,21,4,2,32,3,4,1)
    data=b''
    for (w,h),rgba in zip([(4,2),(2,1),(1,1)],colors):
        pixel=bytes([rgba[2],rgba[1],rgba[0],rgba[3]])*(w*h);data+=pack('I',len(pixel))+pixel
    return chunk(22,chunk(1,pack('HH',1,2))+chunk(21,chunk(1,fields+data)+chunk(3))+chunk(3))
class Server(socketserver.ThreadingMixIn,http.server.HTTPServer):daemon_threads=True
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--require-gpu',action='store_true')
    parser.add_argument('--owner-model',action='append',default=[],help='Optional original model basename; files remain local')
    parser.add_argument('--stock-catalog',type=Path,help='Owner stock IDE manifest, required with --owner-model')
    args=parser.parse_args()
    out=ROOT/'local-only/research/stock-ped-150'/str(time.time_ns());out.mkdir(parents=True)
    files={};events=[];slow=set()
    dff=textured_ped();child=txd([(255,0,0,255),(0,255,0,255),(0,0,255,255)]);parent=txd([(0,0,255,255)]*3)
    def asset(data,ext,delay=False):
        digest=hashlib.sha256(data).hexdigest();path='game/native/stock-img/'+digest+'.'+ext
        files['/'+path]=data;p=out/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
        if delay:slow.add('/'+path)
        return dict(path=path,bytes=len(data),crc32=zlib.crc32(data)&0xffffffff,sha256=digest)
    delayed=chunk(16,dff[12:-12]+chunk(3,chunk(0x1201,b'own-delayed-pedestrian')))
    original_assets={'authored.dff':asset(dff,'dff'),'child.txd':asset(child,'txd'),'parent.txd':asset(parent,'txd'),
                     'delayed.dff':asset(delayed,'dff',True),'static.dff':asset(static_assets()[0],'dff'),
                     'missing_texture.dff':asset(textured_ped('not_in_dictionary'),'dff')}
    models=[dict(id=i,kind=kind,model=model,txd='child',source='data/authored.ide',line=i)for i,kind,model in
            [(100,'ped','authored'),(101,'ped','delayed'),(102,'ped','static'),(103,'ped','missing_texture'),(104,'object','authored'),(105,'ped','absent')]]
    manifest=dict(schema=1,models=models,parents={'child':'parent'},assets=original_assets,vehicleDictionary='vehicle',vehicleGenericFirst=True)
    (out/'manifest.json').write_text(json.dumps(manifest));(out/'child.txd').write_bytes(child)
    owner_hashes={};owner_rows=[];owner_game=ROOT/'local-only/site/game';owner_files=out/'owner-files'
    if args.owner_model:
        assert args.stock_catalog and len(args.owner_model)<=16 and len(set(args.owner_model))==len(args.owner_model)
        assert all(re.fullmatch('[a-z0-9_]{1,40}',name)for name in args.owner_model)
        stock=json.loads(args.stock_catalog.read_text());selected=[];owner_assets={};owner_parents={}
        for name in args.owner_model:
            rows=[r for r in stock['models']if r['kind']=='ped'and r['model']==name];assert len(rows)==1,name
            row=rows[0];selected.append(row);dictionaries=[];current=row['txd']
            while current:
                assert current not in dictionaries and len(dictionaries)<32
                dictionaries.append(current);parent_name=stock['parents'].get(current)
                if parent_name:owner_parents[current]=parent_name
                current=parent_name
            for member in [name+'.dff',*[d+'.txd'for d in dictionaries]]:
                p=owner_game/member;assert 12<=p.stat().st_size<=32*1024*1024
                data=p.read_bytes();digest=hashlib.sha256(data).hexdigest();owner_hashes[str(p.resolve())]=digest
                # The development mirror has per-file links to other archives.
                # Keep the importer's root-containment rule intact: give this
                # local fixture an explicit regular-file source, using clones.
                staged=owner_files/member;staged.parent.mkdir(parents=True,exist_ok=True)
                if not staged.exists():subprocess.run(['/bin/cp','-c',str(p.resolve()),str(staged)],check=True)
                assert not staged.is_symlink()and hashlib.sha256(staged.read_bytes()).hexdigest()==digest
                owner_assets[member]=dict(path=member,bytes=len(data),crc32=zlib.crc32(data)&0xffffffff,sha256=digest)
            skeleton=owner_game/'native/models'/(name+'.skel.bin');assert skeleton.is_file()
            owner_hashes[str(skeleton.resolve())]=hashlib.sha256(skeleton.read_bytes()).hexdigest()
            owner_rows.append(dict(id=row['id'],name=name,skeleton=str(skeleton.resolve())))
        (out/'owner-manifest.json').write_text(json.dumps(dict(schema=1,models=selected,parents=owner_parents,assets=owner_assets,vehicleDictionary='vehicle',vehicleGenericFirst=True)))
    (out/'owner-cases.json').write_text(json.dumps(owner_rows))
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def do_GET(self):
            events.append(dict(path=self.path,encoding=self.headers.get('Accept-Encoding')))
            if self.path in slow:time.sleep(.25)
            data=files.get(self.path)
            if data is None:self.send_error(404);return
            self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers()
            try:self.wfile.write(data)
            except (BrokenPipeError,ConnectionResetError):pass
    paths=[ROOT/'ios/App'/(n+'.swift')for n in ['ServerAddress','NativeStockAssetAccess','NativeSAMPStockModels','NativeSAMPStockAssetLoader',
           'NativeStockPedLoader','NativeRenderWareDFF','NativeRenderWareTXD','NativeRenderWareModel','NativeRenderWareSkeleton',
           'NativeRenderWarePedModel','NativeRenderWareCollision','NativeActorAnimation','NativeFootAnimation','NativeGunAnimation',
           'NativeFlightAnimation','NativeSwimAnimation','NativeRiderAnimation','NativeSkeletalActor']]
    paths+=[Path(__file__).with_suffix('.swift')];frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [*paths,Path(__file__)]}
    cmd=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths),'-o',str(out/'ped-tests')]
    with(out/'build.log').open('w')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=300)
    if r.returncode:print((out/'build.log').read_text()[-6000:]);r.check_returncode()
    server=Server(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
    try:
        r=subprocess.run([str(out/'ped-tests'),str(out),f'http://127.0.0.1:{server.server_port}','required'if args.require_gpu else'optional',owner_files.resolve().as_uri()],capture_output=True,text=True,timeout=180)
        (out/'runtime.log').write_text(r.stdout+r.stderr);(out/'requests.json').write_text(json.dumps(events,indent=2)+'\n')
        report=dict(status='PASS'if r.returncode==0 else'FAIL',exitCode=r.returncode,output=r.stdout+r.stderr,sourceSHA256=frozen,
                    sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),originalFilesUsed=bool(owner_rows),ownerModels=[r['name']for r in owner_rows],
                    scope='Actual authored HTTP/local verification, skeletal/material CPU pipeline and optional Metal byte readback; no renderer/UI/retail claim')
        assert all(v['encoding']=='identity'for v in events)
        original_comparisons=[]
        if r.returncode==0:
            for row in owner_rows:
                actual=(out/('owner-'+row['name']+'.skn.bin')).read_bytes();expected=Path(row['skeleton']).read_bytes()
                ai,af,_=fields(actual);ei,ef,_=fields(expected);assert ai==ei and len(af)==len(ef),row['name']
                maximum=max([abs(a-b)for a,b in zip(af,ef)]or[0]);assert maximum<0.0001,(row['name'],maximum)
                original_comparisons.append(dict(model=row['name'],floatFields=len(af),integerFields=len(ai),maximumSkeletonError=maximum))
        assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in owner_hashes.items())
        report.update(ownerInputsHeld=True,ownerSourceSHA256=owner_hashes,originalSkeletonComparisons=original_comparisons)
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
        print(json.dumps(report));r.check_returncode();assert report['sourcesHeld']
    finally:server.shutdown();server.server_close()
if __name__=='__main__':main()
