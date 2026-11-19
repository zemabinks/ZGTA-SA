#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Owner-local VER2 IMG index and virtual stock assets, without bulk extraction.

Directory layout supporting reference: gta-reversed CDirectory::DirectoryInfo,
file blob cc511650db0669057487dbb1fd3f9e9712c701ca. No reference code is copied.
Logical RW extents come from declared container lengths, never rstrip(0).
All generated metadata/reference bytes must remain owner-local.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import zlib

SECTOR=2048
NAME=re.compile(r'[a-z0-9_#()+.\-]{1,128}\Z')
MAX_ENTRIES=100_000
MAX_FILE=64*1024*1024
MAX_ARCHIVE=8*1024*1024*1024

def exact(handle,at,count):
    if at<0 or count<0:raise ValueError('negative source range')
    handle.seek(at);data=handle.read(count)
    if len(data)!=count:raise ValueError('truncated source range')
    return data

def directory(path):
    path=Path(path);before=path.stat()
    if not path.is_file() or not (SECTOR<=before.st_size<=MAX_ARCHIVE) or before.st_size%SECTOR:
        raise ValueError('IMG size/alignment limit')
    if not NAME.fullmatch(path.name.lower()) or not path.name.lower().endswith('.img'):
        raise ValueError('invalid IMG archive basename')
    with path.open('rb') as handle:
        magic,count=struct.unpack('<4sI',exact(handle,0,8))
        if magic!=b'VER2' or count>MAX_ENTRIES:raise ValueError('unsupported IMG header/count')
        table=exact(handle,8,count*32);end=8+len(table);records=[]
        for at in range(0,len(table),32):
            offset,sectors,packed,raw=struct.unpack_from('<IHH24s',table,at)
            name=raw.split(b'\0',1)[0].decode('ascii').lower()
            if not NAME.fullmatch(name) or not sectors or packed:
                raise ValueError('invalid/packed IMG directory entry')
            offset*=SECTOR;size=sectors*SECTOR
            if offset<end or size>before.st_size-offset:raise ValueError('IMG directory range outside archive')
            records.append({'name':name,'archive':path.name.lower(),'offset':offset,'allocatedBytes':size})
        previous=end
        for record in sorted(records,key=lambda item:item['offset']):
            if record['offset']<previous:raise ValueError('overlapping IMG directory ranges')
            previous=record['offset']+record['allocatedBytes']
    info={'name':path.name.lower(),'bytes':before.st_size,'directoryBytes':end,
          'directorySHA256':hashlib.sha256(magic+struct.pack('<I',count)+table).hexdigest(),
          'mtimeNs':str(before.st_mtime_ns),'entries':count}
    return info,records,(before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)

def logical(handle,record,maximum_file_bytes=MAX_FILE):
    offset,allocated=record['offset'],record['allocatedBytes']
    if not 12<=allocated<=maximum_file_bytes:raise ValueError('allocated file size limit')
    kind,length,_=struct.unpack('<III',exact(handle,offset,12))
    expected=16 if record['name'].endswith('.dff') else 22
    if kind!=expected:raise ValueError('unsupported RW top-level container')
    end=12+length
    if end>allocated:raise ValueError('RW root exceeds allocated range')
    if expected==16 and allocated-end>=12:
        extra=exact(handle,offset+end,12)
        if any(extra):
            extra_kind,extra_length,_=struct.unpack('<III',extra)
            if extra_kind!=3 or extra_length>allocated-end-12:raise ValueError('invalid DFF top-level extension')
            end+=12+extra_length
    tail=allocated-end
    if not 0<=tail<SECTOR:raise ValueError('non-minimal IMG allocation padding')
    padding=exact(handle,offset+end,tail)
    if any(padding):raise ValueError('nonzero IMG allocation tail')
    digest=hashlib.sha256();allocated_digest=hashlib.sha256();crc=0
    for at in range(0,end,64*1024):
        block=exact(handle,offset+at,min(64*1024,end-at))
        digest.update(block);allocated_digest.update(block);crc=zlib.crc32(block,crc)
    allocated_digest.update(padding)
    return {'bytes':end,'crc32':crc,'sha256':digest.hexdigest(),
            'allocatedSHA256':allocated_digest.hexdigest(),'zeroTailBytes':tail}

def generate(paths,manifest,prefix='game/native/stock-img',maximum_file_bytes=MAX_FILE):
    if not (12<=maximum_file_bytes<=MAX_FILE):raise ValueError('file budget')
    if not prefix or any(not NAME.fullmatch(part) or part in ('.','..') for part in prefix.split('/')):
        raise ValueError('invalid virtual URL prefix')
    if len(paths)>8 or not paths:raise ValueError('archive count limit')
    if manifest.get('schema')!=1 or len(manifest.get('models',[]))>30_000 or len(manifest.get('assets',{}))>50_000:
        raise ValueError('invalid stock manifest')
    archives=[];records=[];sources={};fingerprints={}
    for source in paths:
        info,items,fingerprint=directory(source)
        if info['name'] in sources:raise ValueError('duplicate archive basename')
        sources[info['name']]=Path(source);fingerprints[info['name']]=fingerprint
        archives.append(info);records.extend(items)
    if len(records)>MAX_ENTRIES:raise ValueError('aggregate IMG entry limit')
    by_name=collections.defaultdict(list)
    for record in records:
        if record['name'].endswith(('.dff','.txd')):by_name[record['name']].append(record)
    available=[];ambiguous=[];unavailable=[]
    for name,candidates in sorted(by_name.items()):
        if len(candidates)!=1:
            ambiguous.append({'name':name,'candidates':candidates});continue
        record=candidates[0]
        try:
            with sources[record['archive']].open('rb') as handle:value=logical(handle,record,maximum_file_bytes)
            available.append({**record,**value,'path':prefix+'/'+value['sha256']+Path(name).suffix})
        except ValueError as error:unavailable.append({**record,'reason':str(error)})
    for name,path in sources.items():
        stat=path.stat()
        if (stat.st_dev,stat.st_ino,stat.st_size,stat.st_mtime_ns)!=fingerprints[name]:
            raise ValueError('source IMG changed during indexing')
    index={'schema':1,'prefix':prefix,'archives':sorted(archives,key=lambda item:item['name']),
           'entries':available,'ambiguous':ambiguous,'unavailable':unavailable}
    # Keep explicitly supplied non-IMG assets. Any name seen in IMG is replaced
    # only by its unique validated entry; ambiguous/invalid names stay missing.
    output={**manifest,'assets':{k:v for k,v in manifest['assets'].items() if k not in by_name}}
    for entry in available:output['assets'][entry['name']]={key:entry[key] for key in ('path','bytes','crc32','sha256')}
    missing=[];complete=0
    for model in manifest['models']:
        names=[model['model']+'.dff'];seen=set();current=model['txd']
        while current is not None:
            if current in seen or len(seen)>=128:raise ValueError('manifest TXD cycle/depth')
            seen.add(current);names.append(current+'.txd');current=manifest['parents'].get(current)
        absent=[name for name in names if name not in output['assets']]
        if absent:missing.append({'id':model['id'],'files':absent})
        else:complete+=1
    report={'archiveEntries':len(records),'archives':len(archives),'uniqueRWAssets':len(available),
            'logicalBytes':sum(item['bytes'] for item in available),'ambiguousNames':[item['name'] for item in ambiguous],
            'unavailableRWAssets':len(unavailable),'models':len(manifest['models']),'modelsWithCompleteAssetMetadata':complete,
            'modelsMissingAssets':missing,'unavailableReasons':dict(collections.Counter(item['reason'] for item in unavailable)),
            'scope':'Metadata/hash availability only; native format import, gameplay, effects and collision acceptance remain separate. No original file was extracted.'}
    return index,output,report

def write_json(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    encoded=json.dumps(value,sort_keys=True,separators=(',',':')).encode()+b'\n'
    if len(encoded)>32*1024*1024:raise ValueError('generated metadata exceeds 32MiB limit')
    temporary=path.with_suffix(path.suffix+'.tmp')
    temporary.write_bytes(encoded);os.replace(temporary,path)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',action='append',required=True,type=Path)
    parser.add_argument('--manifest',required=True,type=Path)
    parser.add_argument('--index-output',required=True,type=Path)
    parser.add_argument('--manifest-output',required=True,type=Path)
    parser.add_argument('--report-output',required=True,type=Path)
    parser.add_argument('--prefix',default='game/native/stock-img')
    args=parser.parse_args()
    if args.manifest.stat().st_size>16*1024*1024:raise ValueError('stock manifest size limit')
    index,manifest,report=generate(args.archive,json.loads(args.manifest.read_bytes()),args.prefix)
    write_json(args.index_output,index);write_json(args.manifest_output,manifest);write_json(args.report_output,report)
    print(json.dumps({key:value for key,value in report.items() if key!='modelsMissingAssets'},sort_keys=True))

if __name__=='__main__':main()
