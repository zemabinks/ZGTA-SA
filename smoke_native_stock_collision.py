#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Generated catalog/container negatives and optional owner COL/Rapier checks.

Run with --owner-catalog PATH --owner-overlay PATH for an existing local-only
catalog. Optional unmodified DragonFF oracle remains private and is never bundled.
All fixtures, reference results, executables and reports are ignored local-only.
"""
import argparse
import binascii
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import struct
import subprocess

import prepare_native_stock_collision as helper
import smoke_native_renderware_collision as col_test

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'local-only/research/stock-collision/tests'


def img(path, records, packed=0):
    raw = b''.join(records)
    sectors = (len(raw) + 2047) // 2048
    path.write_bytes(b'VER2' + struct.pack('<I', 1) +
                     struct.pack('<IHH24s', 1, sectors, packed, b'own.col') +
                     bytes(2048 - 40) + raw + bytes(sectors * 2048 - len(raw)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owner-catalog', type=Path)
    parser.add_argument('--owner-overlay', type=Path)
    parser.add_argument('--oracle-root', type=Path)
    parser.add_argument('--container-only',action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    library = ROOT/'local-only/native-physics'/('macos-arm64' if platform.machine()=='arm64' else 'macos-x86_64')
    stamp=subprocess.run(['python3',str(ROOT/'native-physics/source_stamp.py'),'check',str(library)],cwd=ROOT)
    assert stamp.returncode==0,'Native host library source stamp is stale'
    archives = OUT / 'archives'; archives.mkdir(exist_ok=True)
    originals = {v: col_test.fixture(v) for v in [1, 2, 3]}
    for version, data in originals.items(): img(archives / f'v{version}.img', [data])
    helper_checks = 0
    def rejects(fn):
        nonlocal helper_checks
        try: fn()
        except (ValueError, UnicodeError): helper_checks += 1; return
        raise AssertionError('Expected bounded IMG/header rejection')
    rejects(lambda: helper.scan([], ['generated']))
    rejects(lambda: helper.scan([archives/'v3.img'], ['../bad']))
    rejects(lambda: helper.generate([archives/'v3.img'], ['generated'], Path('/tmp/public-col')))
    valid_img = (archives/'v3.img').read_bytes()
    for prefix in [0, 4, 7, 8, 31, 39, 40, 2047, 2048, len(valid_img)-1]:
        p = archives / 'truncated.img'; p.write_bytes(valid_img[:prefix])
        rejects(lambda: helper.scan([p], ['generated']))
    for offset, fmt, value in [(0,'4s',b'VER1'), (4,'I',100_001), (8,'I',0),
                               (8,'I',0xffffffff), (12,'H',0), (14,'H',1), (16,'24s',b'../own.col')]:
        b = bytearray(valid_img); struct.pack_into('<'+fmt,b,offset,value)
        p = archives/'mutated.img'; p.write_bytes(b)
        rejects(lambda: helper.scan([p], ['generated']))
    for delta, fmt, value in [(0,'4s',b'COL4'), (4,'I',0xffffffff), (4,'I',0), (8,'22s',b'../bad')]:
        b = bytearray(valid_img); struct.pack_into('<'+fmt,b,2048+delta,value)
        p = archives/'mutated.img'; p.write_bytes(b)
        rejects(lambda: helper.scan([p], ['generated']))
    a = archives/'alias-a.img'; b = archives/'alias-b.img'
    img(a,[originals[3]]); img(b,[originals[3]])
    aliases,_,report = helper.scan([a,b],['generated','absent'])
    assert report['missing']==['absent'] and not report['ambiguous']
    assert len(aliases['generated'])==1 and len(next(iter(aliases['generated'].values()))['sources'])==2
    helper_checks += 2
    distinct,_,report = helper.scan([archives/'v2.img',archives/'v3.img'],['generated'])
    assert report['ambiguous']==['generated'] and len(distinct['generated'])==2
    helper_checks += 1
    loose=OUT/'own-loose.col';loose.write_bytes(originals[1])
    loose_assets,_,loose_report=helper.scan([archives/'v3.img'],['generated'],[('models/coll/own.col',loose)])
    assert len(loose_assets['generated'])==2 and loose_report['explicitCOLFiles'][0]['bytes']==len(originals[1])
    helper_checks+=1

    overlay = OUT/'overlay'; output = overlay/'game/native/stock-collision'
    own_ide=b'objs\n42, generated, generated, 100, 0\n43, absent, generated, 100, 0\nend\n'
    bindings={name:[{'id':i,'source':'data/maps/own.ide','line':line,'sourceSHA256':hashlib.sha256(own_ide).hexdigest()}]
              for name,i,line in [('generated',42,2),('absent',43,3)]}
    manifest,_ = helper.generate([archives/'v3.img'],['generated','absent'],output,bindings=bindings)
    # Completeness is earned from the exact archive index/config sources and
    # every active COLFILE, rather than inferred from an empty name lookup.
    config_root=OUT/'own-game';(config_root/'data/maps').mkdir(parents=True,exist_ok=True)
    configs={'data/default.dat':b'IDE DATA/MAPS/OWN.IDE\nCOLFILE 0 MODELS/COLL/OWN.COL\n',
             'data/gta.dat':b'# own config\n','data/maps/own.ide':own_ide}
    for name,raw in configs.items():(config_root/name).write_bytes(raw)
    stock={'schema':1,'models':[{'id':i,'model':name,'source':'data/maps/own.ide','line':line}
           for name,i,line in [('generated',42,2),('absent',43,3)]],
           'sources':[{'path':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}for name,raw in configs.items()]}
    stock_path=OUT/'own-stock-models.json';stock_path.write_text(json.dumps(stock))
    archive_data=(archives/'v3.img').read_bytes()
    index={'schema':1,'archives':[{'name':'v3.img','bytes':len(archive_data),'directorySHA256':hashlib.sha256(archive_data[:40]).hexdigest()}]}
    index_path=OUT/'own-stock-index.json';index_path.write_text(json.dumps(index))
    complete_args=dict(stock_models=stock_path,stock_index=index_path,game_root=config_root,
                       loose_collections=[('models/coll/own.col',loose)])
    complete_manifest,_=helper.generate([archives/'v3.img'],[],OUT/'coverage-overlay/game/native/stock-collision',**complete_args)
    assert complete_manifest['coverage']['complete'] and complete_manifest['coverage']['stockManifestSHA256']==hashlib.sha256(stock_path.read_bytes()).hexdigest()
    helper_checks+=1
    rejects(lambda:helper.generate([archives/'v3.img'],[],OUT/'coverage-incomplete',**{**complete_args,'loose_collections':[]}))
    rejects(lambda:helper.generate([archives/'v3.img'],[],OUT/'coverage-duplicate',**{**complete_args,'loose_collections':complete_args['loose_collections']*2}))
    broken=copy.deepcopy(index);broken['archives'][0]['directorySHA256']='0'*64
    broken_path=OUT/'wrong-stock-index.json';broken_path.write_text(json.dumps(broken))
    rejects(lambda:helper.generate([archives/'v3.img'],[],OUT/'coverage-wrong-index',**{**complete_args,'stock_index':broken_path}))
    (config_root/'data/gta.dat').write_bytes(b'# changed configuration\n')
    rejects(lambda:helper.generate([archives/'v3.img'],[],OUT/'coverage-wrong-config',**complete_args))
    (config_root/'data/gta.dat').write_bytes(configs['data/gta.dat'])
    rejects(lambda:helper.generate([archives/'v3.img'],['unknown'],OUT/'coverage-unknown-name',**complete_args))
    if args.container_only:
        report={'passed':True,'containerChecks':helper_checks,'coverageProvenanceVerified':True,
                'helperSHA256':hashlib.sha256((ROOT/'prepare_native_stock_collision.py').read_bytes()).hexdigest()}
        (OUT/'container-only-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return
    base_catalog = output/'catalog.json'
    cases,expected,goldens = [],[],{}
    fixtures = OUT/'fixtures'; fixtures.mkdir(exist_ok=True)
    def add(catalog=base_catalog, outcome='rejected', **kwargs):
        row={'catalog':str(catalog),'assetRoot':str(overlay),'id':42,'name':'generated',**kwargs}
        cases.append(row); expected.append(outcome); return len(cases)-1
    def catalog(value, name):
        path=fixtures/(name+'.json');path.write_text(json.dumps(value));return path
    def asset(data, name):
        path=fixtures/(name+'.col');path.write_bytes(data);return path
    def metadata(data, version=3, model_id=42, name='generated'):
        row=copy.deepcopy(manifest['models'][1]['records'][0])
        row.update(bytes=len(data),crc32=binascii.crc32(data)&0xffffffff,
                   sha256=hashlib.sha256(data).hexdigest(),version=version,headerModelID=model_id,headerName=name)
        row['path']='game/native/stock-collision/'+row['sha256']+'.col';return row
    # Manifest rows are sorted: absent, then generated.
    generated_row = manifest['models'][1]
    i=add(outcome='prepared',physics=True);goldens[i]=col_test.golden(3)
    add(outcome='unique',resolveOnly=True,name='GENERATED')
    add(outcome='missing',name='absent',id=43)
    add(outcome='missing',name='not_in_catalog')
    add(id=43);add(id=-1);add(name='../generated')
    add(local=False);add(baseURL='https://name:secret@example.invalid/')
    add(baseURL='ftp://example.invalid/');add(baseURL='https://example.invalid/?token=x')
    add(outcome='unique',baseURL='https://example.invalid/assets/',resolveOnly=True,local=False)
    for prefix in range(len(originals[3])):add(prefix=prefix)
    corrupt=bytearray(originals[3]);corrupt[-1]^=1
    add(data=str(asset(corrupt,'corrupt')))
    for limit in ['bytes','models','file']:add(limit=limit)
    for field,value in [('schema',1),('schema',3)]:
        m=copy.deepcopy(manifest);m[field]=value;add(catalog=catalog(m,'bad-'+str(value)))
    for field,value in [('path','../wrong.col'),('sha256','A'*64),('bytes',-1),('version',4),
                        ('headerName','other'),('headerModelID',43),('sources',[])]:
        m=copy.deepcopy(manifest);m['models'][1]['records'][0][field]=value
        add(catalog=catalog(m,'bad-record-'+field))
    m=copy.deepcopy(manifest);m['models'].append(copy.deepcopy(generated_row));add(catalog=catalog(m,'duplicate-name'))
    m=copy.deepcopy(manifest);m['models'][1]['records']*=2;add(catalog=catalog(m,'duplicate-hash'))
    m=copy.deepcopy(manifest);m['models'][1]['records'][0]['sources']*=2;add(catalog=catalog(m,'duplicate-alias'))
    for field,value in [('id',20000),('source','../wrong.ide'),('line',0),('sourceSHA256','A'*64)]:
        m=copy.deepcopy(manifest);m['models'][1]['bindings'][0][field]=value;add(catalog=catalog(m,'bad-binding-'+field))
    m=copy.deepcopy(manifest);m['models'][1]['bindings']=[];add(catalog=catalog(m,'missing-binding'))
    m=copy.deepcopy(manifest);m['models'][1]['bindings'].append(copy.deepcopy(m['models'][1]['bindings'][0]));add(catalog=catalog(m,'duplicate-binding-id'))
    add(source='data/maps/wrong.ide',line=2)
    add(source='data/maps/own.ide',line=3)
    add(source='data/maps/own.ide')
    add(outcome='unique',source='data/maps/own.ide',line=2,resolveOnly=True)
    for version in [1,2]:
        m=copy.deepcopy(manifest);m['models'][1]['records']=[metadata(originals[version],version)]
        i=add(catalog=catalog(m,'own-col'+str(version)),data=str(asset(originals[version],'own-col'+str(version))),outcome='prepared',physics=True)
        goldens[i]=col_test.golden(version)
    # Header IDs are verified raw hints; exact owner IDE bindings select the
    # requested ID/name. Both zero and nonzero unrelated hints are legitimate.
    for hint in [0,101]:
        raw=originals[3][:30]+struct.pack('<H',hint)+originals[3][32:]
        m=copy.deepcopy(manifest);m['models'][1]['records']=[metadata(raw,3,model_id=hint)]
        i=add(catalog=catalog(m,'valid-hint-'+str(hint)),data=str(asset(raw,'valid-hint-'+str(hint))),outcome='prepared',physics=True)
        golden=col_test.golden(3);golden['id']=hint;goldens[i]=golden
    m=copy.deepcopy(manifest);binding=copy.deepcopy(m['models'][1]['bindings'][0]);binding.update(id=44,line=4)
    m['models'][1]['bindings'].append(binding)
    i=add(catalog=catalog(m,'name-shared-by-two-ide-ids'),id=44,outcome='prepared');goldens[i]=col_test.golden(3)
    for label,raw,version in [('wrong-raw-name',originals[3][:8]+b'other'+bytes(17)+originals[3][30:],3),
                              ('wrong-raw-id',originals[3][:30]+struct.pack('<H',43)+originals[3][32:],3),
                              ('wrong-advertised-version',originals[3],2),
                              ('two-models',originals[3]*2,3)]:
        m=copy.deepcopy(manifest);m['models'][1]['records']=[metadata(raw,version)]
        add(catalog=catalog(m,label),data=str(asset(raw,label)))
    nan=bytearray(originals[3]);struct.pack_into('<f',nan,32,float('nan'))
    m=copy.deepcopy(manifest);m['models'][1]['records']=[metadata(nan)]
    add(catalog=catalog(m,'invalid-geometry'),data=str(asset(nan,'invalid-geometry')))
    # Correct CRC with a contradictory SHA reaches the independent SHA boundary.
    m=copy.deepcopy(manifest);m['models'][1]['records'][0]['sha256']='0'*64
    m['models'][1]['records'][0]['path']='game/native/stock-collision/'+'0'*64+'.col'
    add(catalog=catalog(m,'wrong-sha'),data=str(asset(originals[3],'valid-for-sha')))
    # Same-name distinct records stay ambiguous, with no archive precedence.
    m=copy.deepcopy(manifest);m['models'][1]['records']=[metadata(originals[v],v)for v in [2,3]]
    ambiguous=catalog(m,'ambiguous');add(catalog=ambiguous,outcome='ambiguous');add(catalog=ambiguous,limit='records')
    m=copy.deepcopy(manifest);m['models'][1]['records'][0]['sources'].append({
        'archive':'alias-b.img','collection':'own.col','collectionOffset':2048,'recordOffset':0})
    alias=catalog(m,'aliases');add(catalog=alias,outcome='unique',resolveOnly=True);add(catalog=alias,limit='aliases')
    coverage={'complete':True,'scope':'stock-manifest-img-and-active-colfile','stockManifestSHA256':'1'*64,
              'archiveCount':2,'explicitCOLFiles':[]}
    m=copy.deepcopy(manifest);m['coverage']=coverage;complete=catalog(m,'complete-inventory')
    add(catalog=complete,name='absent',id=43,stockManifestSHA256='1'*64,outcome='no-authored-collision')
    add(catalog=complete,name='absent',id=43,outcome='missing')
    add(catalog=complete,name='absent',id=43,stockManifestSHA256='2'*64,outcome='missing')
    add(catalog=complete,name='unknown',id=44,stockManifestSHA256='1'*64,outcome='missing')
    add(catalog=complete,name='absent',id=42,stockManifestSHA256='1'*64)
    for field,value in [('complete',False),('scope','incomplete'),('stockManifestSHA256','X'*64),('archiveCount',0)]:
        m=copy.deepcopy(manifest);m['coverage']={**coverage,field:value};add(catalog=catalog(m,'bad-coverage-'+field))
    raw_catalog=base_catalog.read_bytes()
    for n in range(0,len(raw_catalog.rstrip()),7):
        p=fixtures/f'json-prefix-{n}.json';p.write_bytes(raw_catalog[:n]);add(catalog=p)
    p=fixtures/'trimmed-json-whitespace.json';p.write_bytes(raw_catalog.rstrip())
    i=add(catalog=p,outcome='prepared');goldens[i]=col_test.golden(3)
    owner_hashes={};owner_count=0;oracle_verified=False
    if args.owner_catalog:
        if not args.owner_overlay:parser.error('--owner-overlay required with --owner-catalog')
        owner=json.loads(args.owner_catalog.read_text())
        if args.oracle_root:col_test.OUT=args.oracle_root
        oracle=col_test.load_oracle()
        for row in owner['models']:
            assert len(row['records'])==1,'This focused owner suite requires unambiguous exact records'
            record=row['records'][0];p=args.owner_overlay/record['path'];raw=p.read_bytes()
            owner_hashes[str(p)]=hashlib.sha256(raw).hexdigest()
            i=add(catalog=args.owner_catalog,assetRoot=str(args.owner_overlay),id=record['headerModelID'],
                  name=row['name'],outcome='prepared',physics=True)
            if oracle:
                ref=oracle.coll();ref.load_memory(raw);assert len(ref.models)==1
                goldens[i]=col_test.oracle_model(ref.models[0]);oracle_verified=True
            owner_count+=1
    input_sources=[ROOT/'ios/App'/n for n in ['NativeSAMPStockCollisionCatalog.swift','NativeRenderWareCollision.swift',
                   'NativeRenderWareCollisionWorld.swift','SwiftRapierWorld.swift']]
    source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in input_sources}
    manifest_path=OUT/'cases.json';manifest_path.write_text(json.dumps(cases))
    binary=OUT/'stock-collision-tests'
    command=['xcrun','swiftc','-Onone','-module-cache-path',str(OUT/'module-cache'),'-I',str(ROOT/'native-physics/include'),
             *map(str,input_sources),str(ROOT/'smoke_native_stock_collision.swift'),'-L',str(library),
             '-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(binary)]
    build=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (OUT/'build.log').write_text(build.stdout);assert build.returncode==0,build.stdout
    run=subprocess.run([str(binary),str(manifest_path),str(OUT/'native-results.json')],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (OUT/'run.log').write_text(run.stdout);assert run.returncode==0,run.stdout
    result=json.loads((OUT/'native-results.json').read_text())
    assert len(result['cases'])==len(cases)
    for index,(actual,wanted)in enumerate(zip(result['cases'],expected)):
        assert actual['outcome']==wanted,(index,cases[index],actual,wanted)
        if index in goldens:col_test.compare(actual['model'],goldens[index])
    for path,digest in {**owner_hashes,**source_hashes}.items():assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,path
    report={'passed':True,'catalogCases':len(cases),'containerChecks':helper_checks,'physicalChecks':result['physicalChecks'],
            'prepared':sum(v=='prepared'for v in expected),'rejected':sum(v=='rejected'for v in expected),
            'ownerModels':owner_count,'ownerFullFieldOracle':oracle_verified,'goldenModels':len(goldens),
            'sourceAndOwnerFilesUnchanged':True,'nativeLibrarySourceStampVerified':True,'ownerHashes':owner_hashes,
            'physics':[row['physics']for row in result['cases']if 'physics'in row]}
    (OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':main()
