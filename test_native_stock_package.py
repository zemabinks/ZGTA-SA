#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual stock package producer on authored files; no compiler/listener/assets."""
from pathlib import Path
from contextlib import contextmanager
import copy
import hashlib
import importlib.util
import json
import os
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zlib
import prepare_native_resource_package as producer
import prepare_native_stock_package as package
from prepare_native_stock_img import generate
from smoke_native_renderware_collision import fixture as col_fixture

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/stock-package-117/tests'


def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(package.encoded(value))


def owned_assets():
    spec=importlib.util.spec_from_file_location('own_rw',ROOT/'tests/artwork_session/fixtures.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    dff,txd=module.assets()
    parent=bytearray(txd);at=txd.index(bytes([0,0,255,255,0,255,0,255]));parent[at]^=1
    return dff,txd,bytes(parent)


def col(name):
    raw=col_fixture(3);return raw[:8]+name.encode().ljust(22,b'\0')+struct.pack('<H',0)+raw[32:]


def image(path,files):
    sector=2048;offset=((8+32*len(files)+sector-1)//sector)*sector;table=[];payload=[]
    for name,data in files:
        allocated=((len(data)+sector-1)//sector)*sector
        table.append(struct.pack('<IHH24s',offset//sector,allocated//sector,0,name.encode()))
        payload.append(data+bytes(allocated-len(data)));offset+=allocated
    header=b'VER2'+struct.pack('<I',len(files))+b''.join(table)
    path.write_bytes(header+bytes((-len(header))%sector)+b''.join(payload))


class PackageCase(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix='own-',dir=OUT);self.root=Path(self.temporary.name)
        self.base=self.root/'base';self.output=self.root/'output';self.source=self.root/'source';self.source.mkdir()
        for name in producer.REQUIRED:
            p=self.base/'site'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(('Authored '+name).encode())
        producer.prepare(self.base)
        self.base_catalog=self.base/'resources-v1/catalog.json'
        dff,txd,parent=owned_assets();self.asset_bytes={'panel.dff':dff,'other.dff':dff,'child.txd':txd,'parent.txd':parent}
        a,b=col('panel'),col('other');self.cols=[a,b]
        self.img=self.source/'own.img';image(self.img,[*self.asset_bytes.items(),('own.col',a+b)])
        source_sha=hashlib.sha256(b'own IDE').hexdigest()
        models=[dict(id=i,kind=k,model=n,txd='child',source='data/maps/own.ide',line=i)for i,n,k in [(9001,'panel','object'),(9002,'other','object'),(9003,'vehicle','vehicle'),(9004,'missing','object'),(9005,'timed','timed')]]
        manifest=dict(schema=1,models=models,parents={'child':'parent'},assets={},vehicleDictionary='vehicle',vehicleGenericFirst=True)
        self.index,self.stock,_=generate([self.img],manifest)
        self.index_path=self.source/'index.json';self.stock_path=self.source/'stock.json';write_json(self.index_path,self.index);write_json(self.stock_path,self.stock)
        collection=next(r for r in self._directory()if r['name']=='own.col');rows=[];offset=0
        self.col_root=self.source/'collision'
        for i,name,data in [(9001,'panel',a),(9002,'other',b)]:
            sha=package.digest(data);path='game/native/stock-collision/'+sha+'.col';p=self.col_root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
            record=dict(path=path,bytes=len(data),crc32=zlib.crc32(data)&0xffffffff,sha256=sha,version=3,headerModelID=0,headerName=name,sources=[dict(archive='own.img',collection='own.col',collectionOffset=collection['offset'],recordOffset=offset)])
            rows.append(dict(name=name,bindings=[dict(id=i,source='data/maps/own.ide',line=i,sourceSHA256=source_sha)],records=[record]));offset+=len(data)
        self.collision=dict(schema=2,models=rows,coverage=dict(complete=True,scope='stock-manifest-img-and-active-colfile',stockManifestSHA256=package.digest(self.stock_path.read_bytes()),archiveCount=1,explicitCOLFiles=[]))
        self.collision_path=self.col_root/package.COL_PATH;write_json(self.collision_path,self.collision)
        self.config=dict(archivePaths={'own.img':str(self.img)},collisionRoot=str(self.col_root),imgIndex=str(self.index_path),stockManifest=str(self.stock_path))
        self.config_path=self.source/'config.json';write_json(self.config_path,self.config)

    def tearDown(self):self.temporary.cleanup()
    def _directory(self):return package.directory(self.img)[1]
    def run_extension(self,ids=(9001,),**kwargs):return package.extend(self.base_catalog,self.output,self.config_path,list(ids),**kwargs)
    def catalog(self):return json.loads((self.output/'resources-v1/catalog.json').read_bytes())
    def metadata(self,name):
        catalog=self.catalog();r=next(r for r in catalog['manifest']['resources']if r['path']==name)
        return json.loads(Path(catalog['files'][r['sha256']]['path']).read_bytes())
    def committed(self):
        self.run_extension();return (self.output/'resources-v1/catalog.json').read_bytes()
    def standalone(self,data=None):
        data=owned_assets()[1]if data is None else data
        self.standalone_file=self.base/'site/game/shared.txd';self.standalone_file.write_bytes(data)
        producer.prepare(self.base)
        meta=dict(path='game/shared.txd',bytes=len(data),sha256=package.digest(data),crc32=zlib.crc32(data)&0xffffffff)
        self.stock['assets']['shared.txd']=meta;next(r for r in self.stock['models']if r['id']==9002)['txd']='shared'
        write_json(self.stock_path,self.stock);self.collision['coverage']['stockManifestSHA256']=package.digest(self.stock_path.read_bytes());write_json(self.collision_path,self.collision)
        self.config['explicitRWPaths']={'game/shared.txd':str(self.standalone_file)};write_json(self.config_path,self.config)
        return meta
    def reject_preserving(self,callback):
        before=(self.output/'resources-v1/catalog.json').read_bytes()
        generations=set((self.output/'resources-v1/generated/stock-package').iterdir())
        with self.assertRaises((ValueError,OSError)):callback()
        self.assertEqual((self.output/'resources-v1/catalog.json').read_bytes(),before)
        self.assertEqual(set((self.output/'resources-v1/generated/stock-package').iterdir()),generations)

    def test_default_profile_unchanged_and_cli_opt_in(self):
        old=json.loads(self.base_catalog.read_bytes());self.assertEqual(len(old['manifest']['resources']),len(producer.REQUIRED))
        (self.source/'accounts.json').write_text('{"must_not_package":"anything"}')
        self.output.mkdir();(self.output/'site').symlink_to(self.source,target_is_directory=True)
        result=subprocess.run([sys.executable,str(ROOT/'prepare_native_resource_package.py'),'--local-only',str(self.output),'--base-catalog',str(self.base_catalog),'--stock-config',str(self.config_path),'--include-stock-model','9001'],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        current=self.catalog();old_rows={r['path']:r for r in old['manifest']['resources']}
        self.assertEqual({r['path']:r for r in current['manifest']['resources']if r['path']in old_rows},old_rows)
        self.assertEqual({k:current['files'][k]for k in old['files']},old['files'])
        self.assertNotIn('accounts',json.dumps(current));self.assertNotIn('archivePaths',json.dumps(current['manifest']))
        self.assertTrue(all(package.stock_namespace(r['path'])or r['path']in old_rows for r in current['manifest']['resources']))
        self.assertNotEqual(old['manifest']['contentID'],current['manifest']['contentID'])

    def test_exact_closure_parent_and_collision_hash_binding(self):
        result=self.run_extension();stock=self.metadata(package.MODEL_PATH);collision=self.metadata(package.COL_PATH)
        self.assertEqual([r['id']for r in stock['models']],[9001]);self.assertEqual(stock['parents'],{'child':'parent'})
        self.assertEqual(set(stock['assets']),{'panel.dff','child.txd','parent.txd'})
        self.assertEqual(collision['coverage']['stockManifestSHA256'],next(r['sha256']for r in self.catalog()['manifest']['resources']if r['path']==package.MODEL_PATH))
        self.assertEqual(collision['models'][0]['bindings'][0]['id'],9001)
        self.assertEqual(result['newLogicalResources'],6);self.assertFalse(result['runtimeImportGPUCollisionAcceptance'])
        for record in stock['assets'].values():
            data=Path(self.catalog()['files'][record['sha256']]['path']).read_bytes()
            self.assertEqual(len(data),record['bytes']);self.assertEqual(package.digest(data),record['sha256']);self.assertEqual(zlib.crc32(data)&0xffffffff,record['crc32'])

    def test_reimport_reuses_but_reverifies_every_stock_blob(self):
        first=self.run_extension();self.base_catalog=self.output/'resources-v1/catalog.json'
        again=self.run_extension();self.assertEqual(first['contentID'],again['contentID']);self.assertEqual(again['writtenBlobs'],0);self.assertEqual(again['reusedVerifiedStockBlobs'],6)
        dff=self.metadata(package.MODEL_PATH)['assets']['panel.dff'];p=Path(self.catalog()['files'][dff['sha256']]['path']);raw=p.read_bytes();p.write_bytes(raw[:-1]+bytes([raw[-1]^1]))
        self.reject_preserving(self.run_extension)

    def test_all_supported_is_explicit_and_reports_gaps(self):
        result=self.run_extension(ids=(),all_supported=True)
        self.assertEqual(result['includedIDs'],[9001,9002]);self.assertEqual({r['id']for r in result['unresolved']},{9003,9004,9005})
        self.assertEqual([r['id']for r in self.metadata(package.MODEL_PATH)['models']],[9001,9002])
        self.reject_preserving(lambda:self.run_extension(ids=(),all_supported=True,maximum_models=1))

    def test_model_and_byte_budgets_preserve_commit(self):
        self.committed();self.reject_preserving(lambda:self.run_extension(maximum_bytes=1))
        self.reject_preserving(lambda:self.run_extension(ids=(9003,)))
        self.reject_preserving(lambda:self.run_extension(ids=(9001,9001)))

    def test_corrupt_source_payload_rejected(self):
        self.committed();row=next(r for r in self.index['entries']if r['name']=='panel.dff')
        with self.img.open('r+b')as stream:stream.seek(row['offset']+12);old=stream.read(1);stream.seek(row['offset']+12);stream.write(bytes([old[0]^1]))
        self.reject_preserving(self.run_extension)

    def test_nonzero_tail_and_wrong_range_rejected(self):
        self.committed();row=next(r for r in self.index['entries']if r['name']=='panel.dff')
        with self.img.open('r+b')as stream:stream.seek(row['offset']+row['bytes']);stream.write(b'X')
        self.reject_preserving(self.run_extension)
        with self.img.open('r+b')as stream:stream.seek(row['offset']+row['bytes']);stream.write(b'\0')
        row['offset']+=2048;write_json(self.index_path,self.index);self.reject_preserving(self.run_extension)

    def test_real_duplicate_img_basename_rejected(self):
        self.committed();other=self.source/'duplicate.img';image(other,[('panel.dff',self.asset_bytes['panel.dff'])])
        info,_,_=package.directory(other);self.index['archives'].append(info);write_json(self.index_path,self.index)
        self.config['archivePaths']['duplicate.img']=str(other);write_json(self.config_path,self.config)
        self.collision['coverage']['archiveCount']=2;write_json(self.collision_path,self.collision)
        self.reject_preserving(self.run_extension)

    def test_catalog_coverage_and_binding_rejected(self):
        self.committed();self.collision['coverage']['stockManifestSHA256']='0'*64;write_json(self.collision_path,self.collision)
        self.reject_preserving(self.run_extension)
        self.collision['coverage']['stockManifestSHA256']=package.digest(self.stock_path.read_bytes());self.collision['models'][0]['bindings'][0]['line']+=1;write_json(self.collision_path,self.collision)
        self.reject_preserving(self.run_extension)

    def test_col_header_and_original_range_identity(self):
        self.committed();row=self.collision['models'][0]['records'][0];row['sources'][0]['recordOffset']=1;write_json(self.collision_path,self.collision)
        self.reject_preserving(self.run_extension)
        row['sources'][0]['recordOffset']=0;row['headerModelID']=99;write_json(self.collision_path,self.collision)
        self.reject_preserving(self.run_extension)

    def test_col_ambiguity_missing_and_child_symlink(self):
        self.committed();row=self.collision['models'][0]['records'][0]
        saved=self.collision['models'].pop(0);write_json(self.collision_path,self.collision);self.reject_preserving(self.run_extension)
        self.collision['models'].insert(0,saved)
        self.collision['models'][0]['records'].append(copy.deepcopy(row));write_json(self.collision_path,self.collision);self.reject_preserving(self.run_extension)
        self.collision['models'][0]['records']=[row];write_json(self.collision_path,self.collision)
        p=self.col_root/row['path'];copy_path=self.source/'same.col';p.rename(copy_path);p.symlink_to(copy_path);self.reject_preserving(self.run_extension)

    def test_explicit_external_col_requires_whole_source_proof(self):
        data=b''.join(self.cols);path=self.source/'own-external.col';path.write_bytes(data);name='data/own-external.col'
        record=self.collision['models'][0]['records'][0]
        record['sources']=[dict(file=name,collection=path.name,collectionOffset=0,recordOffset=0)]
        self.collision['coverage']['explicitCOLFiles']=[dict(path=name,bytes=len(data),sha256=package.digest(data))]
        self.config['explicitCOLPaths']={name:str(path)};write_json(self.config_path,self.config);write_json(self.collision_path,self.collision)
        self.run_extension();self.assertEqual(self.metadata(package.COL_PATH)['models'][0]['records'][0]['sources'],record['sources'])
        record['sources'][0]['collectionOffset']=False;write_json(self.collision_path,self.collision);self.reject_preserving(self.run_extension)
        record['sources'][0]['collectionOffset']=0;self.collision['coverage']['explicitCOLFiles'][0]['sha256']='0'*64
        write_json(self.collision_path,self.collision);self.reject_preserving(self.run_extension)

    def test_empty_authored_inventory_is_explicit(self):
        self.collision['models'][0]['records']=[];write_json(self.collision_path,self.collision)
        result=self.run_extension();self.assertEqual(self.metadata(package.COL_PATH)['models'][0]['records'],[])
        self.assertEqual(result['newLogicalResources'],5)

    def test_traversal_and_duplicate_json_rejected(self):
        self.committed();self.stock['assets']['panel.dff']['path']='game/native/stock-img/../escape.dff';write_json(self.stock_path,self.stock)
        self.collision['coverage']['stockManifestSHA256']=package.digest(self.stock_path.read_bytes());write_json(self.collision_path,self.collision)
        self.reject_preserving(self.run_extension)
        self.config_path.write_text('{"archivePaths":{},"archivePaths":{}}');self.reject_preserving(self.run_extension)

    def test_cancel_partial_stage_preserves_old_commit(self):
        self.committed();generated=self.output/'resources-v1/generated/stock-package'
        def cancelled():return any(any(p.is_file()for p in stage.iterdir())for stage in generated.glob('.stage-*'))
        self.reject_preserving(lambda:self.run_extension(cancelled=cancelled))

    def test_export_reuse_corruption_and_metadata_rollback(self):
        portable=self.root/'portable';self.run_extension(export=portable)
        old_manifest=(portable/'zgta-resources.json').read_bytes();old_catalog=(self.output/'resources-v1/catalog.json').read_bytes()
        original=package.atomic_json
        def failing(path,value):raise OSError('Authored metadata commit failure')
        package.atomic_json=failing
        try:
            with self.assertRaises(OSError):self.run_extension(ids=(9002,),export=portable)
        finally:package.atomic_json=original
        self.assertEqual((portable/'zgta-resources.json').read_bytes(),old_manifest);self.assertEqual((self.output/'resources-v1/catalog.json').read_bytes(),old_catalog)
        blob=next((portable/'blobs').iterdir());blob.write_bytes(b'corrupt')
        with self.assertRaises(ValueError):self.run_extension(export=portable)
        self.assertEqual((portable/'zgta-resources.json').read_bytes(),old_manifest);self.assertEqual((self.output/'resources-v1/catalog.json').read_bytes(),old_catalog)

    def test_late_commit_failure_restores_both_metadata_outputs(self):
        portable=self.root/'portable';self.run_extension(export=portable)
        old_manifest=(portable/'zgta-resources.json').read_bytes();old_catalog=(self.output/'resources-v1/catalog.json').read_bytes();original=package.atomic_json
        def late_failure(path,value):original(path,value);raise OSError('Authored error after atomic replacement')
        package.atomic_json=late_failure
        try:
            with self.assertRaises(OSError):self.run_extension(ids=(9002,),export=portable)
        finally:package.atomic_json=original
        self.assertEqual((portable/'zgta-resources.json').read_bytes(),old_manifest);self.assertEqual((self.output/'resources-v1/catalog.json').read_bytes(),old_catalog)

    def test_portable_repeat_reuses_existing_verified_blobs(self):
        portable=self.root/'portable';first=self.run_extension(export=portable);self.base_catalog=self.output/'resources-v1/catalog.json'
        before={p.name:(p.stat().st_size,p.stat().st_mtime_ns)for p in (portable/'blobs').iterdir()}
        repeated=self.run_extension(export=portable)
        self.assertEqual(first['contentID'],repeated['contentID']);self.assertEqual(repeated['writtenBlobs'],0)
        self.assertEqual(before,{p.name:(p.stat().st_size,p.stat().st_mtime_ns)for p in (portable/'blobs').iterdir()})

    def test_required_core_cannot_be_marked_optional(self):
        self.committed();base=json.loads(self.base_catalog.read_bytes());base['manifest']['resources'][0]['required']=False
        base['manifest']['contentID']=package.manifest_identity(base['manifest']['resources']);write_json(self.base_catalog,base)
        self.reject_preserving(self.run_extension)

    def test_boolean_schema_and_private_configuration_are_rejected(self):
        self.committed();base=json.loads(self.base_catalog.read_bytes());base['manifest']['schema']=True;write_json(self.base_catalog,base)
        self.reject_preserving(self.run_extension)
        base['manifest']['schema']=1;write_json(self.base_catalog,base);self.config['cookie']='must not package';write_json(self.config_path,self.config)
        self.reject_preserving(self.run_extension)

    def test_fifo_and_nonregular_sources_are_rejected_before_open(self):
        fifo=self.source/'not-a-file';os.mkfifo(fifo)
        code='import sys;from pathlib import Path;from prepare_native_stock_package import read_file;read_file(Path(sys.argv[1]),1024)'
        result=subprocess.run([sys.executable,'-c',code,str(fifo)],capture_output=True,text=True,timeout=3)
        self.assertNotEqual(result.returncode,0);self.assertIn('not a bounded regular file',result.stderr)
        with self.assertRaises(ValueError):package.read_file(self.source,1024)

    def test_output_and_portable_symlinks_fail_closed(self):
        elsewhere=self.root/'elsewhere';elsewhere.mkdir();self.output.symlink_to(elsewhere,target_is_directory=True)
        with self.assertRaises(ValueError):self.run_extension()
        self.output.unlink();portable=self.root/'portable';portable.mkdir();(portable/'blobs').symlink_to(elsewhere,target_is_directory=True)
        with self.assertRaises(ValueError):self.run_extension(export=portable)

    def test_standalone_alias_reuses_exact_required_base_blob(self):
        meta=self.standalone();before=self.standalone_file.stat();base=json.loads(self.base_catalog.read_bytes())
        result=self.run_extension(ids=(9002,));alias='game/native/stock-img/'+meta['sha256']+'.txd'
        self.assertEqual(self.metadata(package.MODEL_PATH)['assets']['shared.txd'],dict(meta,path=alias))
        self.assertEqual(self.catalog()['files'][meta['sha256']],base['files'][meta['sha256']])
        self.assertEqual([r for r in self.catalog()['manifest']['resources']if r['path']=='game/shared.txd'],[r for r in base['manifest']['resources']if r['path']=='game/shared.txd'])
        self.assertEqual(len([r for r in self.catalog()['manifest']['resources']if r['path']==alias]),1)
        receipt=json.loads(Path(result['receipt']).read_bytes());self.assertEqual(receipt['standaloneRW'][0]['original'],meta)
        self.assertEqual(receipt['standaloneRW'][0]['outputPath'],alias);self.assertEqual(receipt['standaloneRW'][0]['sourcePath'],str(self.standalone_file))
        self.assertEqual(package.stamp(before),package.stamp(self.standalone_file.stat()))
        self.assertEqual(self.standalone_file.read_bytes(),owned_assets()[1])
        self.assertFalse(any((p/meta['sha256']).exists()for p in (self.output/'resources-v1/generated/stock-package').glob('generation-*')))
        self.assertEqual(self.metadata(package.COL_PATH)['coverage']['stockManifestSHA256'],next(r['sha256']for r in self.catalog()['manifest']['resources']if r['path']==package.MODEL_PATH))
        self.assertNotIn(str(self.standalone_file),json.dumps(self.metadata(package.MODEL_PATH)))

    def test_standalone_missing_mapping_is_explicitly_unresolved(self):
        self.standalone();self.config.pop('explicitRWPaths');write_json(self.config_path,self.config)
        result=self.run_extension(ids=(),all_supported=True);self.assertEqual(result['includedIDs'],[9001])
        missing=next(r for r in result['unresolved']if r['id']==9002);self.assertIn('explicit owned mapping',missing['reason'])
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))

    def test_standalone_missing_wrong_and_ambiguous_mapping_rejected(self):
        self.standalone();self.committed();original=self.standalone_file.read_bytes()
        self.config['explicitRWPaths']['game/shared.txd']=str(self.source/'missing.txd');write_json(self.config_path,self.config)
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
        self.config['explicitRWPaths']['game/shared.txd']=[str(self.standalone_file),str(self.standalone_file)];write_json(self.config_path,self.config)
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
        self.config['explicitRWPaths']['game/shared.txd']=str(self.standalone_file);write_json(self.config_path,self.config)
        self.standalone_file.write_bytes(original[:-1]+bytes([original[-1]^1]));self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
        self.standalone_file.write_bytes(original[:-1]);self.reject_preserving(lambda:self.run_extension(ids=(9002,)))

    def test_standalone_duplicate_json_mapping_rejected(self):
        self.standalone();self.committed();data=package.encoded(self.config).decode()
        fragment=json.dumps('game/shared.txd')+':'+json.dumps(str(self.standalone_file))
        self.assertIn(fragment,data);self.config_path.write_text(data.replace(fragment,fragment+','+fragment,1))
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))

    def test_standalone_exact_required_base_identity_is_mandatory(self):
        self.standalone();self.committed();base=json.loads(self.base_catalog.read_bytes());row=next(r for r in base['manifest']['resources']if r['path']=='game/shared.txd')
        row['required']=False;base['manifest']['contentID']=package.manifest_identity(base['manifest']['resources']);write_json(self.base_catalog,base)
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
        row['required']=True;row['sha256']='0'*64;base['files']['0'*64]=dict(path=str(self.standalone_file),bytes=row['bytes']);base['manifest']['contentID']=package.manifest_identity(base['manifest']['resources']);write_json(self.base_catalog,base)
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))

    def test_standalone_cannot_override_img_or_ambiguous_metadata(self):
        self.standalone();self.committed();self.index.setdefault('ambiguous',[]).append(dict(name='shared.txd',candidates=[]));write_json(self.index_path,self.index)
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
        self.index['ambiguous']=[];write_json(self.index_path,self.index)
        self.stock['assets']['another.txd']=copy.deepcopy(self.stock['assets']['shared.txd']);write_json(self.stock_path,self.stock)
        self.collision['coverage']['stockManifestSHA256']=package.digest(self.stock_path.read_bytes());write_json(self.collision_path,self.collision)
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))

    def test_standalone_txd_root_kind_length_and_crc_are_checked(self):
        original=owned_assets()[1]
        for data in [struct.pack('<I',16)+original[4:],original[:-1],original+b'\0']:
            self.standalone(data);self.committed();self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
        self.standalone();self.stock['assets']['shared.txd']['crc32']^=1;write_json(self.stock_path,self.stock)
        self.collision['coverage']['stockManifestSHA256']=package.digest(self.stock_path.read_bytes());write_json(self.collision_path,self.collision)
        self.reject_preserving(lambda:self.run_extension(ids=(9002,)))

    def test_standalone_mutation_and_replacement_detected_on_real_fd(self):
        self.standalone();self.committed();original_bytes=self.standalone_file.read_bytes();original_reader=package.regular_stream
        for replace in [False,True]:
            touched=[]
            @contextmanager
            def mutating(path,maximum):
                with original_reader(path,maximum)as stream:
                    if Path(path)!=self.standalone_file:yield stream;return
                    class Reader:
                        def fileno(inner):return stream.fileno()
                        def read(inner,count):
                            data=stream.read(count)
                            if data and not touched:
                                touched.append(True)
                                if replace:
                                    other=self.standalone_file.with_suffix('.replacement');other.write_bytes(original_bytes);os.replace(other,self.standalone_file)
                                else:
                                    self.standalone_file.write_bytes(original_bytes[:-1]+bytes([original_bytes[-1]^1]));self.standalone_file.write_bytes(original_bytes)
                            return data
                    yield Reader()
            package.regular_stream=mutating
            try:self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
            finally:package.regular_stream=original_reader
            self.assertEqual(touched,[True]);self.assertEqual(self.standalone_file.read_bytes(),original_bytes)

    def test_standalone_symlink_fifo_and_traversal_fail_closed(self):
        self.standalone();self.committed();other=self.source/'same.txd';other.write_bytes(self.standalone_file.read_bytes())
        self.standalone_file.unlink();self.standalone_file.symlink_to(other);self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
        self.standalone_file.unlink();os.mkfifo(self.standalone_file);self.reject_preserving(lambda:self.run_extension(ids=(9002,)))
        self.config['explicitRWPaths']={'game/../shared.txd':str(other)};write_json(self.config_path,self.config);self.reject_preserving(lambda:self.run_extension(ids=(9002,)))

    def test_standalone_alias_portable_reuse_corrupt_base_and_rollback(self):
        meta=self.standalone();portable=self.root/'portable';self.run_extension(ids=(9002,),export=portable)
        self.base_catalog=self.output/'resources-v1/catalog.json';before=(portable/'blobs'/meta['sha256']).stat();old_catalog=self.base_catalog.read_bytes();old_manifest=(portable/'zgta-resources.json').read_bytes()
        repeated=self.run_extension(ids=(9002,),export=portable);self.assertEqual(repeated['writtenBlobs'],0)
        self.assertEqual(package.stamp(before),package.stamp((portable/'blobs'/meta['sha256']).stat()))
        original=package.atomic_json
        def late_failure(path,value):original(path,value);raise OSError('Authored standalone late commit error')
        package.atomic_json=late_failure
        try:
            with self.assertRaises(OSError):self.run_extension(ids=(9001,9002),export=portable)
        finally:package.atomic_json=original
        self.assertEqual(self.base_catalog.read_bytes(),old_catalog);self.assertEqual((portable/'zgta-resources.json').read_bytes(),old_manifest)
        alternate=self.source/'explicit-copy.txd';alternate.write_bytes(self.standalone_file.read_bytes());self.config['explicitRWPaths']['game/shared.txd']=str(alternate);write_json(self.config_path,self.config)
        self.standalone_file.write_bytes(b'corrupt');self.reject_preserving(lambda:self.run_extension(ids=(9002,)))


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    names=['prepare_native_resource_package.py','prepare_native_stock_package.py','prepare_native_stock_img.py','test_native_stock_package.py','smoke_native_renderware_collision.py','tests/artwork_session/fixtures.py']
    before={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest()for n in names}
    start=time.monotonic();result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PackageCase))
    unchanged=all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==sha for n,sha in before.items())
    report={'status':'PASS'if result.wasSuccessful()and unchanged else'FAIL','tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'seconds':time.monotonic()-start,'sourceUnchanged':unchanged,'sourceHashes':before,'syntheticOnly':True,'noCompilerSocketOrLiveState':True,'enginePlayabilityClaim':False}
    (OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,sort_keys=True));raise SystemExit(0 if report['status']=='PASS'else 1)


if __name__=='__main__':main()
