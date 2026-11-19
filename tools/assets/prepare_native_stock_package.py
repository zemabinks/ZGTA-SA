#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Explicit private prepared-package extension for exact static stock assets.

No source discovery, conversion, network or engine is run. A dependency package
is not proof of native format import, GPU registration or rendered gameplay.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
from contextlib import contextmanager
import copy
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import struct
import tempfile
import uuid
import zlib
from tools.assets.prepare_native_resource_package import REQUIRED, atomic_json, export_catalog, valid_path
from tools.assets.prepare_native_stock_img import directory, logical

SHA=re.compile(r'[0-9a-f]{64}\Z')
NAME=re.compile(r'[a-z0-9_#()+.\-]{1,128}\Z')
MODEL_PATH='game/native/stock-models.json'
COL_PATH='game/native/stock-collision/catalog.json'


def encoded(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()+b'\n'
def digest(value):return hashlib.sha256(value).hexdigest()
def integer(value,low,high):return type(value)is int and low<=value<=high
def stamp(value):return (value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
def check_cancel(cancelled):
    if cancelled():raise ValueError('Stock extension cancelled before commit')


def no_duplicates(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError('Duplicate JSON key')
        result[key]=value
    return result


@contextmanager
def regular_stream(path,maximum):
    path=Path(path);before=path.lstat()
    if not stat.S_ISREG(before.st_mode)or not 0<before.st_size<=maximum:raise ValueError('Stock source is not a bounded regular file')
    flags=os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0)|getattr(os,'O_CLOEXEC',0)
    descriptor=os.open(path,flags)
    with os.fdopen(descriptor,'rb')as stream:
        opened=os.fstat(stream.fileno())
        if not stat.S_ISREG(opened.st_mode)or stamp(opened)!=stamp(before):raise ValueError('Stock source changed before regular-file acquisition')
        yield stream
        if stamp(opened)!=stamp(os.fstat(stream.fileno()))or stamp(opened)!=stamp(path.lstat()):raise ValueError('Stock source changed during read')


def read_file(path,maximum,expected=None):
    with regular_stream(path,maximum)as stream:
        before=os.fstat(stream.fileno())
        data=stream.read(maximum+1)
        if len(data)!=before.st_size or stamp(before)!=stamp(os.fstat(stream.fileno())):raise ValueError('Stock source changed while reading')
    if expected:
        if len(data)!=expected['bytes'] or digest(data)!=expected['sha256'] or zlib.crc32(data)&0xffffffff!=expected['crc32']:
            raise ValueError('Stock source size/SHA256/CRC32 mismatch')
    return data


def read_json(path,maximum=16*1024*1024):
    data=read_file(path,maximum)
    return json.loads(data,object_pairs_hook=no_duplicates),data


def manifest_identity(resources):
    identity=hashlib.sha256(b'zgta-prepared-v1\n')
    for row in resources:
        identity.update((row['path']+'\0'+str(row['bytes'])+'\0'+row['sha256']+'\0'+('1'if row['required']else'0')+'\n').encode())
    return identity.hexdigest()


def validate_base(value):
    manifest=value.get('manifest',{});rows=manifest.get('resources');files=value.get('files')
    if not integer(manifest.get('schema'),1,1) or manifest.get('profile')!='zgta-prepared-v1' or not isinstance(rows,list) or not 1<=len(rows)<=200000 or not isinstance(files,dict):raise ValueError('Private prepared base catalog required')
    names=set();required=set();total=0;last=''
    for row in rows:
        name=row.get('path','');sha=row.get('sha256','')
        if not valid_path(name) or name in names or name<last or not SHA.fullmatch(sha) or not integer(row.get('bytes'),1,2147483648) or type(row.get('required'))is not bool:raise ValueError('Invalid base resource record/order')
        names.add(name);last=name;total+=row['bytes']
        if row['required']:required.add(name)
        file=files.get(sha,{})
        if not integer(file.get('bytes'),1,2147483648)or file['bytes']!=row['bytes'] or not isinstance(file.get('path'),str) or not Path(file['path']).is_absolute():raise ValueError('Base resource has no exact private file mapping')
    if total>256*1024**3 or not REQUIRED.issubset(required) or manifest_identity(rows)!=manifest.get('contentID'):raise ValueError('Base manifest identity/core required dependency mismatch')
    return copy.deepcopy(rows),copy.deepcopy(files)


def under(root,name):
    if not valid_path(name):raise ValueError('Invalid logical stock path')
    root=Path(root).resolve(strict=True);target=root/name
    current=root
    for part in Path(name).parts:
        current=current/part
        if current.is_symlink():raise ValueError('Stock child symlink is not an exact resource')
    if not target.resolve(strict=True).is_relative_to(root):raise ValueError('Stock path escapes configured root')
    return target


def stock_namespace(name):
    return name==MODEL_PATH or name==COL_PATH or name.startswith(('game/native/stock-img/','game/native/stock-collision/'))


def verified_directory(path):
    """Same authored VER2 layout as the index producer, on a retained safe FD."""
    path=Path(path)
    if not NAME.fullmatch(path.name.lower())or not path.name.lower().endswith('.img'):raise ValueError('Invalid configured IMG basename')
    with regular_stream(path,8*1024**3)as stream:
        before=os.fstat(stream.fileno());size=before.st_size
        if size<2048 or size%2048:raise ValueError('IMG allocation alignment')
        header=stream.read(8)
        if len(header)!=8:raise ValueError('Truncated IMG header')
        magic,count=struct.unpack('<4sI',header)
        if magic!=b'VER2'or count>100000 or count*32>size-8:raise ValueError('IMG directory count/header')
        table=stream.read(count*32)
        if len(table)!=count*32:raise ValueError('Truncated IMG directory')
        records=[];minimum=8+len(table)
        for first in range(0,len(table),32):
            sector,sectors,packed,raw=struct.unpack_from('<IHH24s',table,first)
            name=raw.split(b'\0',1)[0].decode('ascii').lower();offset=sector*2048;allocated=sectors*2048
            if not NAME.fullmatch(name)or packed or not allocated or offset<minimum or offset+allocated>size:raise ValueError('IMG directory range/name')
            records.append({'name':name,'archive':path.name.lower(),'offset':offset,'allocatedBytes':allocated})
        previous=minimum
        for record in sorted(records,key=lambda row:row['offset']):
            if record['offset']<previous:raise ValueError('Overlapping IMG allocations')
            previous=record['offset']+record['allocatedBytes']
        return {'name':path.name.lower(),'bytes':size,'directoryBytes':minimum,'directorySHA256':digest(header+table),'entries':count},records,stamp(before)


def asset_metadata(value,extension,require_stock_address=True):
    if not isinstance(value,dict) or not integer(value.get('bytes'),12,32*1024*1024) or not integer(value.get('crc32'),0,0xffffffff) or not SHA.fullmatch(value.get('sha256','')):raise ValueError('Invalid stock asset identity/runtime file budget')
    expected='game/native/stock-img/'+value['sha256']+'.'+extension
    if not valid_path(value.get('path','')):raise ValueError('Invalid stock source logical path')
    if require_stock_address and value.get('path')!=expected:raise ValueError('Stock asset address differs from its identity')
    return value


def read_standalone_txd(source,cancelled):
    """Exact configured/base identity, on one retained bounded regular FD."""
    expected=source['original'];sha=hashlib.sha256();crc=0;data=bytearray()
    with regular_stream(source['sourcePath'],32*1024*1024)as stream:
        if os.fstat(stream.fileno()).st_size!=expected['bytes']:raise ValueError('Standalone RW source size differs from metadata')
        while len(data)<expected['bytes']:
            check_cancel(cancelled);block=stream.read(min(65536,expected['bytes']-len(data)))
            if not block:raise ValueError('Truncated standalone RW source')
            data.extend(block);sha.update(block);crc=zlib.crc32(block,crc)
        check_cancel(cancelled)
        if stream.read(1)or sha.hexdigest()!=expected['sha256']or crc&0xffffffff!=expected['crc32']:raise ValueError('Standalone RW source size/SHA256/CRC32 mismatch')
        kind,length,_=struct.unpack_from('<III',data)
        if kind!=22 or length!=len(data)-12:raise ValueError('Standalone TXD must be one exact declared texture dictionary')
    return bytes(data)


def regular_output(path):
    path=Path(path).absolute()
    for item in [path,*path.parents]:
        if item.is_symlink():raise ValueError('Stock output must not write through a symlink')
    path.mkdir(parents=True,exist_ok=True)
    if not path.is_dir():raise ValueError('Stock output is not a regular directory')
    return path


def extend(base_catalog,local,config_path,model_ids,*,all_supported=False,maximum_models=64,
           maximum_bytes=128*1024*1024,export=None,cancelled=lambda:False):
    if not integer(maximum_models,1,30000) or not integer(maximum_bytes,1,32*1024**3):raise ValueError('Stock package limits')
    if all_supported and model_ids:raise ValueError('Choose explicit models or --all-supported, not both')
    if any(not integer(i,1,19999)for i in model_ids) or len(set(model_ids))!=len(model_ids):raise ValueError('Invalid or duplicate requested stock model')
    check_cancel(cancelled)
    base,_=read_json(base_catalog,96*1024*1024);old_rows,old_files=validate_base(base)
    config_path=Path(config_path).absolute();config,_=read_json(config_path,131072)
    allowed={'archivePaths','collisionRoot','imgIndex','stockManifest','explicitCOLPaths','explicitRWPaths'}
    if set(config)-allowed or not {'archivePaths','collisionRoot','imgIndex','stockManifest'}.issubset(config):raise ValueError('Unexpected private stock configuration fields')
    def configured(value):
        if not isinstance(value,str)or not value:raise ValueError('Invalid configured source path')
        return (config_path.parent/value).absolute()if not Path(value).is_absolute()else Path(value)
    stock_path=configured(config['stockManifest']);stock,stock_bytes=read_json(stock_path)
    col_root=configured(config['collisionRoot']);collision,col_bytes=read_json(under(col_root,COL_PATH))
    index,index_bytes=read_json(configured(config['imgIndex']),32*1024*1024)
    if not integer(stock.get('schema'),1,1) or not isinstance(stock.get('models'),list) or len(stock['models'])>30000 or not isinstance(stock.get('assets'),dict) or len(stock['assets'])>50000 or not isinstance(stock.get('parents'),dict):raise ValueError('Invalid source stock manifest')
    coverage=collision.get('coverage',{})
    if not integer(collision.get('schema'),2,2) or not isinstance(collision.get('models'),list) or len(collision['models'])>30000 or coverage.get('complete')is not True or coverage.get('scope')!='stock-manifest-img-and-active-colfile' or coverage.get('stockManifestSHA256')!=digest(stock_bytes) or not integer(coverage.get('archiveCount'),1,16):raise ValueError('Source COL inventory is not bound to the exact stock manifest')
    if not integer(index.get('schema'),1,1) or index.get('prefix')!='game/native/stock-img' or not isinstance(index.get('archives'),list) or not 1<=len(index['archives'])<=8 or not isinstance(index.get('entries'),list) or len(index['entries'])>100000:raise ValueError('Invalid source IMG index')
    if coverage['archiveCount']!=len(index['archives']) or not NAME.fullmatch(stock.get('vehicleDictionary',''))or type(stock.get('vehicleGenericFirst'))is not bool:raise ValueError('Stock source scope/dictionary identity')
    explicit=config.get('explicitCOLPaths',{})
    if not isinstance(explicit,dict)or len(explicit)>256 or any(not valid_path('game/'+name)or not name.lower().endswith('.col')or not isinstance(value,str)for name,value in explicit.items()):raise ValueError('Invalid explicit COL file mapping')
    explicit_rw=config.get('explicitRWPaths',{})
    if not isinstance(explicit_rw,dict)or len(explicit_rw)>256 or any(not valid_path(name)or not name.endswith('.txd')or name.startswith('game/native/stock-img/')or not isinstance(value,str)or not value for name,value in explicit_rw.items()):raise ValueError('Invalid explicit standalone RW mapping')
    required_rows={row['path']:row for row in old_rows if row['required']}
    for name in explicit_rw:
        matches=[asset for asset in stock['assets'].values()if isinstance(asset,dict)and asset.get('path')==name]
        old=required_rows.get(name)
        if len(matches)!=1 or old is None or any(old.get(key)!=matches[0].get(key)for key in ['bytes','sha256']):raise ValueError('Standalone RW mapping needs one exact required base resource')
    models={};col_models={}
    for row in stock['models']:
        if not integer(row.get('id'),0,19999)or row['id']in models or not NAME.fullmatch(row.get('model',''))or not NAME.fullmatch(row.get('txd',''))or not valid_path('game/'+row.get('source',''))or not integer(row.get('line'),1,1000000):raise ValueError('Invalid stock model binding')
        models[row['id']]=row
    for row in collision['models']:
        name=row.get('name','')
        if not NAME.fullmatch(name)or name in col_models:raise ValueError('Duplicate/invalid COL model name')
        col_models[name]=row
    prior=next((r for r in old_rows if r['path']==MODEL_PATH),None)
    previous_ids=set()
    if prior:
        old=old_files[prior['sha256']];data=read_file(old['path'],16*1024*1024)
        if len(data)!=prior['bytes']or digest(data)!=prior['sha256']:raise ValueError('Existing stock metadata failed re-import verification')
        previous_ids={r['id']for r in json.loads(data,object_pairs_hook=no_duplicates)['models']}
    candidates=sorted(models)if all_supported else sorted(set(model_ids)|previous_ids)
    selected=[];unresolved=[];needed={};selected_cols=[];parent_links={};standalone_sources={}
    for model_id in candidates:
        try:
            row=models[model_id]
            if row.get('kind')not in ('object','weapon'):raise ValueError('unsupported kind '+str(row.get('kind')))
            names=[row['model']+'.dff'];chain=[];current=row['txd']
            while current is not None:
                if not NAME.fullmatch(current)or current in chain or len(chain)>=32:raise ValueError('TXD parent cycle/depth')
                chain.append(current);names.append(current+'.txd');current=stock['parents'].get(current)
            assets={};model_standalone={}
            for name in names:
                extension=name.rsplit('.',1)[1];original=asset_metadata(stock['assets'].get(name),extension,False)
                canonical='game/native/stock-img/'+original['sha256']+'.'+extension
                if original['path']==canonical:assets[name]=original;continue
                if original['path']not in explicit_rw:raise ValueError('Standalone RW path requires an explicit owned mapping')
                if extension!='txd'or Path(original['path']).name!=name:raise ValueError('Standalone mapping is not an exact TXD basename')
                assets[name]={**original,'path':canonical}
                model_standalone[name]={'name':name,'original':copy.deepcopy(original),'sourcePath':str(configured(explicit_rw[original['path']])),'outputPath':canonical}
            col=copy.deepcopy(col_models.get(row['model']))
            if not col or not isinstance(col.get('records'),list)or len(col['records'])>1:raise ValueError('missing or ambiguous authored COL inventory')
            binding=[b for b in col.get('bindings',[])if b.get('id')==model_id and b.get('source')==row['source']and b.get('line')==row['line']and SHA.fullmatch(b.get('sourceSHA256',''))]
            if len(binding)!=1:raise ValueError('COL IDE binding differs from selected model')
            col['bindings']=binding
        except (ValueError,KeyError,TypeError)as error:
            if not all_supported:raise ValueError('Stock model '+str(model_id)+': '+str(error))from error
            unresolved.append({'id':model_id,'reason':str(error)});continue
        selected.append(row);needed.update(assets);selected_cols.append(col);standalone_sources.update(model_standalone)
        for child,parent in zip(chain,chain[1:]):parent_links[child]=parent
    if not selected or len(selected)>maximum_models:raise ValueError('Selected static candidates exceed model limit (or none available): '+str(len(selected)))
    merged_cols={}
    for col in selected_cols:
        if col['name']in merged_cols:merged_cols[col['name']]['bindings'].extend(col['bindings'])
        else:merged_cols[col['name']]=col
    selected_cols=list(merged_cols.values())
    col_records=[record for row in selected_cols for record in row['records']]
    metadata_bytes=sum(a['bytes']for a in {a['sha256']:a for a in needed.values()}.values())+sum(r.get('bytes',0)for r in {r.get('sha256'):r for r in col_records}.values())
    if metadata_bytes>maximum_bytes:raise ValueError('Selected stock bytes exceed explicit package budget')
    archive_paths=config['archivePaths']
    if not isinstance(archive_paths,dict)or len(archive_paths)>8:raise ValueError('Explicit IMG paths required')
    physical={};raw_names={};index_names={}
    for entry in index['entries']:
        name=entry.get('name','')
        if name in index_names:raise ValueError('Duplicate IMG indexed basename')
        index_names[name]=entry
    indexed_names=set(index_names)|{row.get('name')for row in index.get('ambiguous',[])}|{row.get('name')for row in index.get('unavailable',[])}
    if indexed_names.intersection(standalone_sources):raise ValueError('Standalone RW mapping cannot override an IMG candidate')
    for info in index['archives']:
        name=info.get('name','')
        if not NAME.fullmatch(name)or name in physical or name not in archive_paths:raise ValueError('IMG archive identity/configuration')
        path=configured(archive_paths[name])
        if path.is_symlink():raise ValueError('IMG source symlink is ambiguous')
        actual,records,fingerprint=verified_directory(path)
        if any(actual.get(k)!=info.get(k)for k in ['name','bytes','directoryBytes','directorySHA256','entries']):raise ValueError('IMG directory differs from pinned index')
        physical[name]=(path,fingerprint,records)
        for record in records:raw_names.setdefault(record['name'],[]).append(record)
    output=regular_output(Path(local)/'resources-v1');generated=regular_output(output/'generated/stock-package')
    if export:
        regular_output(export);regular_output(Path(export)/'blobs')
        if (Path(export)/'zgta-resources.json').is_symlink():raise ValueError('Portable manifest symlink')
    lock_path=output/'.stock-extension.lock'
    if (lock_path.exists()or lock_path.is_symlink())and not stat.S_ISREG(lock_path.lstat().st_mode):raise ValueError('Output lock is not a regular file')
    descriptor=os.open(lock_path,os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0),0o600)
    with os.fdopen(descriptor,'a+b')as lock:
        if not stat.S_ISREG(os.fstat(lock.fileno()).st_mode):raise ValueError('Output lock descriptor is not regular')
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise ValueError('Stock output is already being prepared')
        return _write(base,old_rows,old_files,stock,collision,selected,needed,selected_cols,parent_links,unresolved,
                      physical,raw_names,index_names,col_root,config,configured,output,generated,maximum_bytes,export,cancelled,standalone_sources,
                      {'stockManifestSHA256':digest(stock_bytes),'collisionCatalogSHA256':digest(col_bytes),'imgIndexSHA256':digest(index_bytes),'allSupportedRequested':all_supported})


def _write(base,old_rows,old_files,stock,collision,selected,needed,selected_cols,parents,unresolved,
           physical,raw_names,index_names,col_root,config,configured,output,generated,maximum_bytes,export,cancelled,standalone_sources,provenance):
    new_files={};resources=[];resource_paths={};reused=0;written=0;total=0;final=None;committed=False
    if export and (Path(export)/'zgta-resources.json').is_file()and (Path(export)/'zgta-resources.json').stat().st_size>96*1024*1024:raise ValueError('Old portable manifest byte bound')
    previous_export=(Path(export)/'zgta-resources.json').read_bytes()if export and (Path(export)/'zgta-resources.json').is_file()else None
    catalog_path=output/'catalog.json'
    if (catalog_path.exists()or catalog_path.is_symlink())and not stat.S_ISREG(catalog_path.lstat().st_mode):raise ValueError('Prepared output catalog is not regular')
    if catalog_path.is_file()and catalog_path.stat().st_size>96*1024*1024:raise ValueError('Old output metadata byte bound')
    previous_catalog=catalog_path.read_bytes()if catalog_path.is_file()else None
    def restore(path,previous):
        current=path.read_bytes()if path.is_file()else None
        if current==previous:return
        if previous is None:path.unlink(missing_ok=True)
        else:
            temporary=path.with_name('.stock-rollback-'+uuid.uuid4().hex);temporary.write_bytes(previous);os.replace(temporary,path)
    def restore_export():
        if export:
            path=Path(export)/'zgta-resources.json'
            restore(path,previous_export)
    try:
        with tempfile.TemporaryDirectory(prefix='.stage-',dir=generated)as stage_name:
            stage=Path(stage_name);final=generated/('generation-'+uuid.uuid4().hex)
            def add(name,data,crc=None):
                nonlocal reused,written,total
                check_cancel(cancelled)
                sha=digest(data);crc=zlib.crc32(data)&0xffffffff if crc is None else crc
                if name in resource_paths:
                    if resource_paths[name]!=(sha,len(data)):raise ValueError('Conflicting logical stock resource')
                    return
                resource_paths[name]=(sha,len(data))
                total+=len(data)
                if total>maximum_bytes:raise ValueError('Stock byte budget including metadata')
                prior=old_files.get(sha)
                if prior:
                    read_file(prior['path'],64*1024*1024,{'bytes':len(data),'sha256':sha,'crc32':crc});new_files[sha]=copy.deepcopy(prior);reused+=1
                elif sha not in new_files:
                    path=stage/sha
                    with path.open('xb')as stream:
                        for at in range(0,len(data),65536):check_cancel(cancelled);stream.write(data[at:at+65536])
                        stream.flush();os.fsync(stream.fileno())
                    read_file(path,64*1024*1024,{'bytes':len(data),'sha256':sha,'crc32':crc})
                    new_files[sha]={'path':str((final/sha).absolute()),'bytes':len(data)};written+=1
                resources.append({'path':name,'bytes':len(data),'sha256':sha,'required':True})
            for name,meta in sorted(needed.items()):
                check_cancel(cancelled)
                if name in standalone_sources:
                    if raw_names.get(name):raise ValueError('Standalone RW mapping conflicts with an original IMG basename')
                    # add() must reuse this hash's already-required base mapping;
                    # a standalone source cannot create a new payload body.
                    if meta['sha256']not in old_files:raise ValueError('Standalone RW base blob is unavailable')
                    data=read_standalone_txd(standalone_sources[name],cancelled)
                    add(meta['path'],data,meta['crc32']);continue
                matches=raw_names.get(name,[]);entry=index_names.get(name)
                if len(matches)!=1 or not entry or any(entry.get(k)!=matches[0][k]for k in ['archive','name','offset','allocatedBytes']):raise ValueError('Missing or ambiguous exact IMG range: '+name)
                if any(entry.get(k)!=meta[k]for k in ['path','bytes','crc32','sha256']):raise ValueError('Stock manifest/index identity mismatch')
                path=physical[entry['archive']][0]
                with regular_stream(path,8*1024**3)as stream:
                    measured=logical(stream,entry)
                    if any(measured[k]!=entry.get(k)for k in ['bytes','crc32','sha256','allocatedSHA256','zeroTailBytes']):raise ValueError('IMG logical range/hash/padding changed')
                    stream.seek(entry['offset']);data=stream.read(entry['bytes'])
                if stamp(path.stat())!=physical[entry['archive']][1]:raise ValueError('IMG source changed')
                if len(data)!=meta['bytes']or digest(data)!=meta['sha256']or zlib.crc32(data)&0xffffffff!=meta['crc32']:raise ValueError('IMG payload integrity')
                add(meta['path'],data,meta['crc32'])
            for row in selected_cols:
                for record in row['records']:
                    if not integer(record.get('bytes'),72,32*1024*1024)or not SHA.fullmatch(record.get('sha256',''))or record.get('path')!='game/native/stock-collision/'+record['sha256']+'.col' or not integer(record.get('crc32'),0,0xffffffff)or not integer(record.get('headerModelID'),0,65535)or not integer(record.get('version'),1,3):raise ValueError('Invalid selected COL record')
                    data=read_file(under(col_root,record['path']),32*1024*1024,record)
                    version={b'COLL':1,b'COL2':2,b'COL3':3}.get(data[:4]);name=data[8:30].split(b'\0',1)[0].decode('ascii').lower();header_id=struct.unpack_from('<H',data,30)[0]
                    if struct.unpack_from('<I',data,4)[0]+8!=len(data)or version!=record.get('version')or name!=row['name']or record.get('headerName','').lower()!=name or header_id!=record.get('headerModelID'):raise ValueError('COL header identity differs from exact binding')
                    proven=False
                    for source in record.get('sources',[]):
                        check_cancel(cancelled)
                        if (source.get('archive')is None)==(source.get('file')is None):raise ValueError('COL source has ambiguous ownership')
                        if source.get('archive')in physical:
                            path,_,entries=physical[source['archive']];collections=[r for r in entries if r['name']==source.get('collection')and r['offset']==source.get('collectionOffset')]
                            if len(collections)!=1:raise ValueError('COL collection has no exact IMG source')
                            collection=collections[0];offset=source.get('recordOffset')
                            if not integer(offset,0,collection['allocatedBytes']-len(data)):raise ValueError('COL record range outside collection')
                            with regular_stream(path,8*1024**3)as stream:
                                cursor=0
                                while cursor<offset:
                                    stream.seek(collection['offset']+cursor);header=stream.read(8)
                                    if header[:4]not in (b'COLL',b'COL2',b'COL3')or len(header)!=8:raise ValueError('COL record is not at a validated container boundary')
                                    length=struct.unpack_from('<I',header,4)[0]+8
                                    if length<72 or length>collection['allocatedBytes']-cursor:raise ValueError('COL collection record bounds')
                                    cursor+=length
                                if cursor!=offset:raise ValueError('COL record begins inside another record')
                                stream.seek(collection['offset']+offset);actual=stream.read(len(data))
                            if stamp(path.stat())!=physical[source['archive']][1]:raise ValueError('COL IMG source changed')
                        elif source.get('file')in config.get('explicitCOLPaths',{}):
                            path=configured(config['explicitCOLPaths'][source['file']]);whole=read_file(path,32*1024*1024)
                            proof=[r for r in collision['coverage'].get('explicitCOLFiles',[])if r.get('path')==source['file']]
                            if len(proof)!=1 or proof[0].get('bytes')!=len(whole)or proof[0].get('sha256')!=digest(whole)or not integer(source.get('collectionOffset'),0,0)or Path(source['file']).name.lower()!=str(source.get('collection','')).lower():raise ValueError('Explicit COL source inventory identity')
                            offset=source.get('recordOffset');cursor=0
                            if not integer(offset,0,len(whole)-len(data)):raise ValueError('Explicit COL record bounds')
                            while cursor<offset:
                                if cursor+8>len(whole)or whole[cursor:cursor+4]not in (b'COLL',b'COL2',b'COL3'):raise ValueError('Explicit COL record boundary')
                                count=struct.unpack_from('<I',whole,cursor+4)[0]+8
                                if count<72 or count>len(whole)-cursor:raise ValueError('Explicit COL record size')
                                cursor+=count
                            if cursor!=offset:raise ValueError('Explicit COL offset begins inside a record')
                            actual=whole[offset:offset+len(data)]
                        else:raise ValueError('COL source requires an explicit owned archive/file mapping')
                        if actual!=data:raise ValueError('COL overlay differs from original source range')
                        proven=True
                    if not proven:raise ValueError('COL record has no validated original provenance')
                    add(record['path'],data,record['crc32'])
            reduced={'schema':1,'models':selected,'parents':parents,'assets':needed,'vehicleDictionary':stock.get('vehicleDictionary'),'vehicleGenericFirst':stock.get('vehicleGenericFirst')}
            stock_data=encoded(reduced)
            coverage=copy.deepcopy(collision['coverage']);coverage['stockManifestSHA256']=digest(stock_data)
            reduced_col={'schema':2,'models':selected_cols,'coverage':coverage}
            col_data=encoded(reduced_col)
            if len(stock_data)>16*1024*1024 or len(col_data)>16*1024*1024:raise ValueError('Runtime stock metadata byte limit')
            add(MODEL_PATH,stock_data);add(COL_PATH,col_data)
            rows=[r for r in old_rows if not stock_namespace(r['path'])]+resources
            rows.sort(key=lambda r:r['path'])
            if len({r['path']for r in rows})!=len(rows)or len(rows)>200000 or sum(r['bytes']for r in rows)>256*1024**3:raise ValueError('Merged prepared catalog bounds/duplicate paths')
            files={sha:old_files[sha]for sha in {r['sha256']for r in rows}if sha in old_files};files.update(new_files)
            manifest={'schema':1,'profile':'zgta-prepared-v1','contentID':manifest_identity(rows),'resources':rows}
            receipt={**provenance,'includedIDs':[m['id']for m in selected],'unresolved':unresolved,'newLogicalResources':len(resources),'newLogicalBytes':total,'writtenBlobs':written,'reusedVerifiedStockBlobs':reused,'baseVisualRowsUnchanged':True,'baseIntegrityBoundary':'Canonical metadata verified/reused; old visual payloads are not rehashed unless explicitly exporting. Native installation verifies payloads before activation.','baseContentID':base['manifest']['contentID'],'contentID':manifest['contentID'],'runtimeImportGPUCollisionAcceptance':False,'configsPackaged':False,'approvedSourceRootsInferred':False}
            if standalone_sources:receipt['standaloneRW']=[copy.deepcopy(standalone_sources[name])for name in sorted(standalone_sources)]
            (stage/'receipt.json').write_bytes(encoded(receipt));check_cancel(cancelled)
            os.replace(stage,final)
            check_cancel(cancelled)
            if export:export_catalog(manifest,files,Path(export))
            check_cancel(cancelled)
            atomic_json(output/'catalog.json',{'manifest':manifest,'files':files});committed=True
            return {**receipt,'resources':len(rows),'uniqueBlobs':len(files),'catalog':str(output/'catalog.json'),'receipt':str(final/'receipt.json'),'exported':bool(export)}
    except BaseException:
        if not committed:
            restore_export();restore(catalog_path,previous_catalog)
        raise
    finally:
        if not committed and final and final.exists():shutil.rmtree(final)
