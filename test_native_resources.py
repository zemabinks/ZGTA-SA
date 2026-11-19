#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual resource producer/HTTP/Swift persistence regressions; synthetic bytes only."""
from pathlib import Path
import base64, hashlib, http.client as http_client, importlib.util, json, os, secrets, shutil, signal, socket, struct, subprocess, sys, time
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/resources-107'
SWIFT=['ServerAddress.swift','NativeStockAssetAccess.swift','NativeResourceManifest.swift','NativeResourceStore.swift','NativeResourceSession.swift']
ANIMATION_SWIFT=['NativeSkeletalActor.swift','NativeActorAnimation.swift','NativeFootAnimation.swift','NativeGunAnimation.swift','NativeSwimAnimation.swift','NativeFlightAnimation.swift','NativeRiderAnimation.swift']
SERVER=['serve_local.js','browser_recovery_hook.js','browser_task_policy.js','browser_recovery.js','native_resource_server.js','stock_native_assets.js','stock_img_assets.js','native_radio_server.js','radio_streams.js', 'radio_metadata.js','prepare_native_radio_audio.py','selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js', 'player_placement.js']
REQUIRED=['game/world/index.json','game/native/models/index.json','game/native/vehicles.physics.json','game/native/foot-animation.json','game/native/models/animations.clips.bin','game/native/weapons.json','game/native/seating.json','game/native/riders.json']

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value):path.write_text(json.dumps(value,indent=2)+'\n')
def run(command,cwd,log,timeout=180,env=None):
    p=subprocess.Popen(command,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True,env=env)
    try:output,_=p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGTERM)
        try:output,_=p.communicate(timeout=3)
        except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);output,_=p.communicate()
        log.write_text(output);raise RuntimeError('Bounded subprocess timeout: '+Path(command[0]).name)
    log.write_text(output)
    return p.returncode,output

def free_port():
    with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def http(port,route,method='GET',headers=None,body=None):
    c=http_client.HTTPConnection('127.0.0.1',port,timeout=5)
    try:
        c.request(method,route,body=body,headers=headers or {});r=c.getresponse();data=r.read(4*1024*1024+1)
        if len(data)>4*1024*1024:raise ValueError('Fixture response budget')
        return r.status,dict(r.getheaders()),data
    finally:c.close()

def synthetic_animation_carriers():
    # Independently authored real CLP1/SKN1 layouts consumed by the production
    # animation reader: one idle clip with root+pelvis, two frames/bones and
    # three skin vertices. No magic-only stub is used as the positive fixture.
    string=lambda value:struct.pack('<H',len(value.encode()))+value.encode()
    clip=bytearray(b'CLP1'+struct.pack('<III',1,0,1))
    clip+=string('ped/idle_stance')+struct.pack('<fI',1.0,2)
    for bone,positioned in [(0,1),(1,0)]:
        clip+=struct.pack('<iII',bone,2,positioned)
        for when in [0.0,1.0]:
            clip+=struct.pack('<5f',when,0,0,0,1)
            if positioned:clip+=struct.pack('<3f',0,0,0)
    identity=struct.pack('<16f',1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)
    skin=bytearray(b'SKN1'+struct.pack('<III',3,2,2)+identity+identity)
    for parent,bone in [(-1,0),(0,1)]:skin+=struct.pack('<ii',parent,bone)+identity
    for frame in [0,1]:skin+=struct.pack('<I',frame)+identity
    for point in [(0,0,0),(1,0,0),(0,0,1)]:skin+=struct.pack('<3f4B4f',*point,0,0,0,0,1,0,0,0)
    return bytes(clip),bytes(skin)

def synthetic_animation_mesh(vertices=3):
    data=bytearray(b'WRL2'+struct.pack('<III',vertices,3,1))
    points=[(0,0,0),(1,0,0),(0,0,1)]
    for index in range(vertices):data+=struct.pack('<3f',*points[index%3])
    data+=bytes(vertices*8)+struct.pack('<III',0,min(1,vertices-1),min(2,vertices-1))
    data+=bytes([255])*(vertices*4)+bytes((vertices+vertices%2)*2)+bytes([255])*(vertices*4)+bytes(2)
    return bytes(data)

def test_animation_selection(snapshot,work,check,report):
    # Call the immutable actual producer function, never a replacement filter.
    spec=importlib.util.spec_from_file_location('resource_producer_under_test',snapshot/'prepare_native_resource_package.py')
    producer=importlib.util.module_from_spec(spec);spec.loader.exec_module(producer)
    library,skeleton=synthetic_animation_carriers();base=work/'animation-selection';base.mkdir()
    def patch(data,offset,value):
        result=bytearray(data);result[offset:offset+len(value)]=value;return bytes(result)
    cases=[
        ('valid-paired-skeletal-family',library,skeleton,False),
        ('legacy-family-missing-skeleton',library,None,True),
        ('legacy-family-missing-library',None,skeleton,True),
        ('wrong-library-magic',b'CLP0'+library[4:],skeleton,True),
        ('short-library-magic',b'CLP',skeleton,True),
        ('truncated-library-header',b'CLP1',skeleton,True),
        ('truncated-library-body',library[:-1],skeleton,True),
        ('wrong-library-version',patch(library,12,struct.pack('<I',2)),skeleton,True),
        ('wrong-skeleton-magic',library,b'SKN0'+skeleton[4:],True),
        ('short-skeleton-magic',library,b'SKN',True),
        ('truncated-skeleton-header',library,b'SKN1',True),
        ('truncated-skeleton-body',library,skeleton[:-1],True),
        ('empty-skeleton-vertices',library,patch(skeleton,4,struct.pack('<I',0)),True),
        ('oversized-skeleton-bone-count',library,patch(skeleton,12,struct.pack('<I',65)),True),
    ]
    native_cases=[]
    report['animationSelection']={'scope':'Actual immutable producer selection over independently authored complete CLP1/SKN1 carriers and malformed variants; not engine rendering acceptance','cases':[]}
    for label,clip,skin,retain in cases:
        local=base/label/'local-only';models=local/'site/game/native/models';models.mkdir(parents=True)
        (models/'synthetic-ped.bin').write_bytes(synthetic_animation_mesh())
        baked=models/'synthetic-ped.anim.bin';baked.write_bytes(b'ANIM-independent-legacy-fallback')
        if clip is not None:(models/'animations.clips.bin').write_bytes(clip)
        if skin is not None:(models/'synthetic-ped.skel.bin').write_bytes(skin)
        selected=producer.candidates(local);actual='game/native/models/synthetic-ped.anim.bin' in selected
        details={'expectedBakedRetained':retain,'actualBakedRetained':actual,'libraryBytes':len(clip) if clip is not None else None,'skeletonBytes':len(skin) if skin is not None else None}
        report['animationSelection']['cases'].append({'label':label,**details})
        check(actual==retain,'actual producer skeletal selection '+label,details)
        native_cases.append({'label':label,'library':str(models/'animations.clips.bin') if clip is not None else None,'skeleton':str(models/'synthetic-ped.skel.bin') if skin is not None else None,'vertexCount':3,'libraryValid':not ('library' in label and label!='valid-paired-skeletal-family'),'skeletonValid':not ('skeleton' in label)})
    # Exact paired names and producer working-overlay precedence are significant.
    local=base/'working-override/local-only';models=local/'site/game/native/models';models.mkdir(parents=True)
    (models/'animations.clips.bin').write_bytes(library)
    (models/'synthetic-ped.bin').write_bytes(synthetic_animation_mesh())
    (models/'synthetic-ped.anim.bin').write_bytes(b'ANIM-independent-legacy-fallback')
    (models/'unrelated-ped.skel.bin').write_bytes(skeleton)
    check('game/native/models/synthetic-ped.anim.bin' in producer.candidates(local),'actual producer never pairs a differently named skeleton')
    (models/'synthetic-ped.skel.bin').write_bytes(skeleton)
    working=local/'native-working/models';working.mkdir(parents=True);(working/'synthetic-ped.skel.bin').write_bytes(b'NOT-SKN1')
    selected=producer.candidates(local)
    check('game/native/models/synthetic-ped.anim.bin' in selected and selected['game/native/models/synthetic-ped.skel.bin']==working/'synthetic-ped.skel.bin','actual producer malformed working skeleton cannot borrow valid archived skeleton')
    (working/'synthetic-ped.skel.bin').write_bytes(skeleton)
    check('game/native/models/synthetic-ped.anim.bin' not in producer.candidates(local),'actual producer valid working skeleton excludes only matching baked family')

    mesh=models/'synthetic-ped.bin';mesh.unlink()
    check('game/native/models/synthetic-ped.anim.bin' in producer.candidates(local),'actual producer missing paired mesh retains baked fallback')
    mesh.write_bytes(synthetic_animation_mesh(4))
    check('game/native/models/synthetic-ped.anim.bin' in producer.candidates(local),'actual producer skeleton mesh vertex mismatch retains baked fallback')
    mesh.write_bytes(b'WRL2'+struct.pack('<III',3,3,1))
    check('game/native/models/synthetic-ped.anim.bin' in producer.candidates(local),'actual producer truncated paired mesh retains baked fallback')
    mesh.write_bytes(synthetic_animation_mesh())
    native_config=work/'animation-readers.json';save(native_config,{'cases':native_cases,'output':str(work/'animation-readers-report.json')})
    executable=work/'verify-animation-readers'
    command=['swiftc','-swift-version','5','-parse-as-library','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules']+[str(snapshot/'ios/App'/n) for n in ANIMATION_SWIFT]+[str(snapshot/'test_native_resources_animation.swift'),'-o',str(executable)]
    code,text=run(command,work,work/'animation-readers-compile.log',180)
    check(code==0,'actual native animation readers compile for independent selection oracle',text[-2000:] if code else None)
    if code==0:
        code,text=run([str(executable),str(native_config)],work,work/'animation-readers.log',60)
        check(code==0,'actual native CLP1 and SKN1 readers validate authored selection carriers',text[-2000:] if code else None)
        if (work/'animation-readers-report.json').exists():report['animationReaders']=json.loads((work/'animation-readers-report.json').read_text())


def main():
    OUT.mkdir(parents=True,exist_ok=True);work=OUT/('run-'+str(time.time_ns()));work.mkdir();snapshot=work/'source';snapshot.mkdir();report={'schema':1,'started':time.time(),'work':str(work),'cases':[],'scope':'Synthetic resource bytes, actual immutable producer/server/Swift code; no engine playability, UI, device or retail acceptance'}
    sources=[ROOT/'ios/App'/n for n in SWIFT+ANIMATION_SWIFT]+[ROOT/n for n in SERVER+['prepare_native_resource_package.py','test_native_resources.py','test_native_resources.swift','test_native_resources_server.js','test_native_resources_animation.swift']]
    hashes={str(p.relative_to(ROOT)):digest(p) for p in sources}
    for p in sources:
        dest=snapshot/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
    report['sourceBefore']=hashes;helper=gate=None;handles=[];probes=[]
    def check(value,label,details=None):
        report['cases'].append({'label':label,'passed':bool(value),**({'details':details} if details is not None else {})})
        if not value:print('RESOURCE_PY_FAILED '+label,flush=True)
    def prepare(local,export,label):
        code,text=run([sys.executable,str(snapshot/'prepare_native_resource_package.py'),'--local-only',str(local),'--export',str(export)],work,work/(label+'.log'))
        if code:raise RuntimeError('Actual resource producer failed: '+text[-1000:])
        return json.loads(text)
    try:
        test_animation_selection(snapshot,work,check,report)
        local=work/'host/local-only';site=local/'site';site.mkdir(parents=True)
        for name in REQUIRED:
            target=site/name;target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes((json.dumps({'syntheticFixture':name})+'\n').encode() if name.endswith('.json') else synthetic_animation_carriers()[0])
        (site/'game/world/synthetic.bin').write_bytes(b'WRL2'+struct.pack('<III',2,0,0))
        (site/'game/world/synthetic.png').write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nVQAAAAASUVORK5CYII='))
        payload=site/'game/native/test-payload.bin';phases={};packages={}
        for phase in ['A','B','C']:
            payload.write_bytes((phase+'-independent-resource-fixture\n').encode()*7)
            package=work/('package-'+phase);result=prepare(local,package,'producer-'+phase);packages[phase]=package
            catalog=work/('catalog-'+phase+'.json');shutil.copy2(local/'resources-v1/catalog.json',catalog);data=work/('payload-'+phase+'.bin');shutil.copy2(payload,data)
            raw=json.loads(catalog.read_text());resource=next(x for x in raw['manifest']['resources'] if x['path']=='game/native/test-payload.bin')
            phases[phase]={'catalog':str(catalog),'payload':str(data),'digest':resource['sha256']};report['producer'+phase]=result
            if phase=='A':
                again=prepare(local,package,'producer-A-repeat');report['producerRepeat']=again
                check(again['hashedFiles']==0 and again['reusedHashReceipts']==again['resources'],'actual producer reuses all unchanged hash receipts')
        check(report['producerB']['hashedFiles']==1,'actual producer rehashes one changed source')
        check(report['producerA']['contentID']!=report['producerB']['contentID'],'actual producer changes snapshot identity')
        malformed_local=work/'malformed/local-only';shutil.copytree(local,malformed_local)
        (malformed_local/'site/game/native/riders.json').write_text('{"wrongSyntheticSchema":true}')
        malformed_package=work/'package-malformed';report['producerMalformed']=prepare(malformed_local,malformed_package,'producer-malformed')
        # Invalid export source with a sparse >2GiB file is rejected before hashing.
        prior_catalog=(local/'resources-v1/catalog.json').read_bytes();oversized=site/'game/native/oversized.bin'
        with oversized.open('wb') as f:f.truncate(2_147_483_649)
        code,text=run([sys.executable,str(snapshot/'prepare_native_resource_package.py'),'--local-only',str(local)],work,work/'producer-oversize.log')
        check(code!=0 and 'per-file size' in text,'actual producer rejects per-file resource budget');oversized.unlink()
        check((local/'resources-v1/catalog.json').read_bytes()==prior_catalog,'failed producer preserves previous catalog transaction')
        allowed=json.loads((packages['A']/'zgta-resources.json').read_text())['resources'];ready=work/'http-ready.json'
        helper_config=work/'http-config.json';save(helper_config,{'module':str(snapshot/'native_resource_server.js'),'localOnly':str(local),'phases':phases,'readyFile':str(ready),'allowedPaths':[x['path'] for x in allowed]})
        helper_log=(work/'http-helper.log').open('w');handles.append(helper_log);helper=subprocess.Popen(['node',str(snapshot/'test_native_resources_server.js'),str(helper_config)],cwd=work,stdout=helper_log,stderr=subprocess.STDOUT,start_new_session=True)
        limit=time.time()+10
        while not ready.exists() and time.time()<limit and helper.poll() is None:time.sleep(.025)
        if not ready.exists():raise RuntimeError('Resource helper not ready')
        hosts=json.loads(ready.read_text());swift_config={'work':str(work/'store'),'a':hosts['a'],'b':hosts['b'],'packageA':str(packages['A']),'packageB':str(packages['B']),'packageMalformed':str(malformed_package),'output':str(work/'swift-suite.json')};(work/'store').mkdir();config=work/'swift-config.json';save(config,swift_config)
        executable=work/'verify-resources';command=['swiftc','-swift-version','5','-parse-as-library','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules']+[str(snapshot/'ios/App'/n) for n in SWIFT]+[str(snapshot/'test_native_resources.swift'),'-o',str(executable)]
        code,text=run(command,work,work/'swift-compile.log',180);check(code==0,'actual immutable Swift resource sources compile',text[-2000:] if code else None)
        if code==0:
            code,text=run([str(executable),str(config),'suite'],work,work/'swift-suite.log',180);check(code==0,'actual Swift resource persistence/network suite',text[-2000:] if code else None)
            if (work/'swift-suite.json').exists():report['swiftSuite']=json.loads((work/'swift-suite.json').read_text())
            # Separate process reopens ApplicationSupport-style root after listenerA was stopped.
            swift_config['output']=str(work/'swift-reopen.json');save(config,swift_config)
            code,text=run([str(executable),str(config),'reopen'],work,work/'swift-reopen.log',60);check(code==0,'new Swift process reopens installed resources offline',text[-1200:] if code else None)
            if (work/'swift-reopen.json').exists():report['swiftReopen']=json.loads((work/'swift-reopen.json').read_text())
        # Actual serve_local.js enforces its normal gates before manifest/blob module.
        gate_root=work/'gate';gate_root.mkdir()
        for name in SERVER:shutil.copy2(snapshot/name,gate_root/name)
        gate_local=gate_root/'local-only';shutil.copytree(local,gate_local)
        (gate_local/'selfhost').mkdir(exist_ok=True);(gate_local/'selfhost/client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
        code,text=run([sys.executable,str(snapshot/'prepare_native_resource_package.py'),'--local-only',str(gate_local),'--verify'],work,work/'producer-gate.log');check(code==0,'actual gate fixture catalog bound to its own resources')
        port=free_port();assert port not in [8766,8780,8801,8803,8804,8805,8806]
        approved='resources-qa.invalid:'+str(port);code_secret=secrets.token_hex(24);env={**os.environ,'ZGTA_BROWSER_TASK_POLICY_PLAN':'','ZGTA_SELFHOST':'1','PORT':str(port),'BIND_HOST':'127.0.0.1','ZGTA_JOIN_CODE':code_secret,'ZGTA_JOIN_CODE_FILE':'','ZGTA_ALLOWED_HOSTS':approved}
        gate_log=(work/'gated-http.log').open('w');handles.append(gate_log);gate=subprocess.Popen(['node','serve_local.js'],cwd=gate_root,env=env,stdout=gate_log,stderr=subprocess.STDOUT,start_new_session=True)
        limit=time.time()+10
        while time.time()<limit and gate.poll() is None:
            try:
                if http(port,'/api/local/status')[0]==200:break
            except OSError:pass
            time.sleep(.05)
        manifest_route='/game/native/resource-manifest.json';cat=json.loads((gate_local/'resources-v1/catalog.json').read_text());key=next(iter(cat['files']));blob_route='/game/native/resource-blobs/'+key
        for route in [manifest_route,blob_route]:
            check(http(port,route,headers={'Host':'foreign.invalid'})[0]==421,'Host gate precedes '+route.split('/')[-1])
            check(http(port,route,headers={'Host':approved,'Origin':'http://foreign.invalid'})[0]==403,'Origin gate precedes '+route.split('/')[-1])
            check(http(port,route,headers={'Host':approved})[0]==401,'join gate precedes '+route.split('/')[-1])
        status,headers,body=http(port,'/api/local/join','POST',{'Host':approved,'Content-Type':'application/json'},json.dumps({'code':code_secret}));check(status==200,'normal fixture first-party join')
        cookie=headers.get('Set-Cookie','').split(';')[0];assert cookie.startswith('zgta_access=');auth={'Host':approved,'Origin':'http://'+approved,'Cookie':cookie}
        for route in [manifest_route,blob_route]:
            status,headers,body=http(port,route,headers=auth);check(status==200 and len(body)>0,'authorized actual resource GET '+route.split('/')[-1])
            if route==blob_route:check(hashlib.sha256(body).hexdigest()==key,'actual module serves exact named hash bytes')
            status,headers,body=http(port,route,'HEAD',auth);check(status==200 and body==b'' and int(headers.get('Content-Length','0'))>0,'authorized actual resource HEAD '+route.split('/')[-1])
            check(http(port,route,'POST',auth,b'{}')[0]==405,'resource module rejects mutation method '+route.split('/')[-1])
        check(http(port,'/game/native/resource-blobs/%2fetc%2fpasswd',headers=auth)[0]==404,'blob hash route rejects encoded path traversal')
        # Mutate only this synthetic fixture's private catalog; not production data.
        saved=(gate_local/'resources-v1/catalog.json').read_bytes();outside=work/'outside.bin';outside.write_bytes(b'outside-fixture')
        escaped=gate_local/'site/game/escape.bin';escaped.symlink_to(outside)
        altered=json.loads(saved);altered['files'][key]={'path':str(escaped),'bytes':outside.stat().st_size};save(gate_local/'resources-v1/catalog.json',altered)
        escape_status,escape_headers,escape_body=http(port,blob_route,headers=auth)
        check(escape_status in [403,404,409] and escape_body!=outside.read_bytes(),'actual module rejects symlink escape outside approved resource roots',{'observedStatus':escape_status,'servedOutsideBytes':escape_body==outside.read_bytes()})
        (gate_local/'resources-v1/catalog.json').write_bytes(saved)
        altered=json.loads(saved);altered['files'][key]['path']=str(outside);save(gate_local/'resources-v1/catalog.json',altered)
        check(http(port,blob_route,headers=auth)[0]==403,'actual module rejects explicit outside-root blob path')
        # Preserve legitimate owner archive roots while refusing undeclared child escapes.
        def launch_probe(probe_local,label):
            config_file=work/(label+'-config.json');ready_file=work/(label+'-ready.json')
            save(config_file,{'module':str(snapshot/'native_resource_server.js'),'probeLocalOnly':str(probe_local),'readyFile':str(ready_file)})
            log=(work/(label+'.log')).open('w');handles.append(log)
            process=subprocess.Popen(['node',str(snapshot/'test_native_resources_server.js'),str(config_file)],cwd=work,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);probes.append(process)
            limit=time.time()+5
            while not ready_file.exists() and process.poll() is None and time.time()<limit:time.sleep(.025)
            if not ready_file.exists():raise RuntimeError('Resource source-root probe not ready: '+label)
            return json.loads(ready_file.read_text())['port']
        linked=work/'linked/local-only';(linked/'site').mkdir(parents=True);(linked/'site/game').symlink_to(site/'game',target_is_directory=True)
        code,text=run([sys.executable,str(snapshot/'prepare_native_resource_package.py'),'--local-only',str(linked)],work,work/'producer-linked.log');check(code==0,'actual producer indexes an intentional game-root symlink')
        linked_catalog=json.loads((linked/'resources-v1/catalog.json').read_text());linked_item=next(r for r in linked_catalog['manifest']['resources'] if r['path']=='game/native/foot-animation.json')
        probe_port=launch_probe(linked,'root-symlink');status,headers,body=http(probe_port,'/game/native/resource-blobs/'+linked_item['sha256'])
        check(status==200 and hashlib.sha256(body).hexdigest()==linked_item['sha256'],'actual module preserves intentional approved root symlinks')
        archive=work/'explicit-owner-archive';archive.mkdir();(archive/'extra.bin').write_bytes(b'explicit-owner-root-synthetic-bytes')
        extra_link=site/'game/native/extra-archive';extra_link.symlink_to(archive,target_is_directory=True)
        explicit=work/'explicit/local-only';(explicit/'site').mkdir(parents=True);(explicit/'site/game').symlink_to(site/'game',target_is_directory=True)
        code,text=run([sys.executable,str(snapshot/'prepare_native_resource_package.py'),'--local-only',str(explicit)],work,work/'producer-explicit-root.log');check(code==0,'actual producer indexes synthetic archive declaration fixture')
        explicit_catalog=json.loads((explicit/'resources-v1/catalog.json').read_text());extra_item=next(r for r in explicit_catalog['manifest']['resources'] if r['path']=='game/native/extra-archive/extra.bin')
        undeclared_port=launch_probe(explicit,'undeclared-source-root');route='/game/native/resource-blobs/'+extra_item['sha256']
        check(http(undeclared_port,route)[0] in [403,404],'catalog blob cannot implicitly authorize a foreign archive root')
        save(explicit/'resource-source-roots.json',[str(archive)])
        declared_port=launch_probe(explicit,'declared-source-root');status,headers,body=http(declared_port,route)
        check(status==200 and hashlib.sha256(body).hexdigest()==extra_item['sha256'],'explicit private archive-root authorization permits exact resource bytes')

    except Exception as error:
        report['fatal']=str(error);print('RESOURCE_REGRESSION_FATAL '+str(error),flush=True)
    finally:
        for p in [helper,gate]+probes:
            if p and p.poll() is None:
                os.killpg(p.pid,signal.SIGTERM)
                try:p.wait(timeout=3)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
        for handle in handles:handle.close()
        after={str(p.relative_to(ROOT)):digest(p) for p in sources};report['sourceAfter']=after;report['sourceUnchanged']=after==hashes;report['finished']=time.time()
        report['status']='INVALIDATED' if after!=hashes else ('PASS' if not report.get('fatal') and all(c['passed'] for c in report['cases']) else 'FAIL')
        save(work/'report.json',report);save(OUT/'latest.json',{'work':str(work),'report':str(work/'report.json'),'status':report['status']})
        print('RESOURCE_REGRESSION '+report['status']+' '+str(work),flush=True)
    return 0 if report['status']=='PASS' else 1
if __name__=='__main__':sys.exit(main())
