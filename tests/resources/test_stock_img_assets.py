#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Generated VER2/RW malformed bounds plus actual indexed owner range checks."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import tools.assets.prepare_native_stock_img as img

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/stock-img/tests';OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('stock_img_fixtures',ROOT/'tests/artwork_session/fixtures.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
dff,txd=fixture.assets();checks=0
# Valid unknown RW plugin with meaningful declared payload zeros at EOF.
dff=fixture.chunk(16,dff[12:-12]+fixture.chunk(3,fixture.chunk(0x1201,b'own-payload\0\0')))

def check(value):
    global checks
    checks+=1;assert value

def archive(path,rows):
    sector=(8+32*len(rows)+2047)//2048;directory=bytearray(b'VER2'+struct.pack('<I',len(rows)));payload=[]
    for name,data,extra,nonzero in rows:
        count=(len(data)+2047)//2048+extra
        directory.extend(struct.pack('<IHH24s',sector,count,0,name.encode()))
        block=data+bytes(count*2048-len(data))
        if nonzero:block=block[:-1]+b'\1'
        payload.append(block);sector+=count
    path.write_bytes(directory+bytes((-len(directory))%2048)+b''.join(payload))

with tempfile.TemporaryDirectory(dir=OUT,prefix='generated-') as temporary:
    work=Path(temporary);first=work/'generated.img';second=work/'other.img'
    extension=dff+fixture.chunk(3)
    rows=[('panel.dff',dff,0,False),('extra.dff',extension,0,False),('child.txd',txd,0,False),('unique.txd',txd,0,False),
          ('bad.dff',struct.pack('<III',16,0xffffffff,0),0,False),('nonzero.txd',txd,0,True),
          ('wholezero.txd',txd,1,False),('uv_anim.dff',fixture.chunk(43),0,False)]
    archive(first,rows);archive(second,[('child.txd',txd,0,False)])
    manifest={'schema':1,'models':[{'id':1000,'kind':'object','model':'panel','txd':'child','source':'data/test.ide','line':1},
                                {'id':1001,'kind':'object','model':'extra','txd':'unique','source':'data/test.ide','line':2}],
              'parents':{},'vehicleDictionary':'vehicle','vehicleGenericFirst':True,
              'assets':{'child.txd':{'path':'unrelated/fallback.txd','bytes':12,'crc32':0,'sha256':'0'*64}}}
    index,stock,report=img.generate([first,second],manifest)
    check(len(index['entries'])==3 and len(index['unavailable'])==4 and len(index['ambiguous'])==1)
    check('child.txd' not in stock['assets'])
    check(report['modelsWithCompleteAssetMetadata']==1 and report['modelsMissingAssets'][0]['files']==['child.txd'])
    for name,data in [('panel.dff',dff),('extra.dff',extension),('unique.txd',txd)]:
        entry=next(item for item in index['entries'] if item['name']==name)
        check(entry['bytes']==len(data) and entry['sha256']==hashlib.sha256(data).hexdigest())
        check(entry['zeroTailBytes']==entry['allocatedBytes']-len(data))
    base=first.read_bytes()
    def reject(label,mutate):
        path=work/(label+'.img');value=bytearray(base);mutate(value);path.write_bytes(value)
        try:img.directory(path)
        except (ValueError,UnicodeDecodeError):check(True)
        else:raise AssertionError('accepted malformed IMG '+label)
    reject('magic',lambda v:v.__setitem__(slice(0,4),b'VER1'))
    reject('count',lambda v:struct.pack_into('<I',v,4,100001))
    reject('range',lambda v:struct.pack_into('<I',v,8,0xffffffff))
    reject('overlap',lambda v:struct.pack_into('<I',v,40,struct.unpack_from('<I',v,8)[0]))
    reject('table-range',lambda v:struct.pack_into('<I',v,8,0))
    reject('packed',lambda v:struct.pack_into('<H',v,14,1))
    reject('path',lambda v:v.__setitem__(slice(16,40),b'../../evil.dff\0'.ljust(24,b'\0')))
    reject('nonascii',lambda v:v.__setitem__(16,128))
    malformed=work/'short.img';malformed.write_bytes(base[:-1])
    try:img.directory(malformed)
    except ValueError:check(True)
    else:raise AssertionError('accepted misaligned archive')
    original=img.logical
    def mutate_source(handle,record,maximum):
        result=original(handle,record,maximum)
        value=bytearray(first.read_bytes());value[-1]^=1;first.write_bytes(value)
        return result
    img.logical=mutate_source
    try:
        try:img.generate([first,second],manifest)
        except ValueError as error:check('changed' in str(error))
        else:raise AssertionError('accepted mutation while hashing')
    finally:img.logical=original;first.write_bytes(base)
    config={'index':str(work/'index.json'),'archives':{'generated.img':str(first),'other.img':str(second)},'expected':{},'invalidIndexes':[]}
    img.write_json(config['index'],index)
    for name,data in [('panel.dff',dff),('extra.dff',extension),('unique.txd',txd)]:
        path=work/name;path.write_bytes(data);config['expected'][name]=str(path)
    for label,change in [('forged-range',lambda value:value['entries'][0].update(offset=value['entries'][0]['offset']+2048)),
                         ('forged-url',lambda value:value['entries'][0].update(path='../escape.dff')),
                         ('forged-hash',lambda value:value['entries'][0].update(sha256='wrong')),
                         ('omit-ambiguity',lambda value:value.update(ambiguous=[]))]:
        value=copy.deepcopy(index);change(value);path=work/(label+'.json');img.write_json(path,value);config['invalidIndexes'].append(str(path))
    actual=ROOT/'local-only/research/stock-img/index.json'
    source=ROOT.parent/'ZGTA-SA-core-102/local-only/research/stock-models'
    if actual.exists() and (source/'extracted-eight/extraction-report.json').exists():
        extraction=json.loads((source/'extracted-eight/extraction-report.json').read_text())
        config['owner']={'indexPath':str(actual),'archivePaths':{name:str(source/'retail-img/models'/name) for name in ['gta3.img','gta_int.img']},
                         'expected':[{'name':item['name'],'sha256':item['logicalSHA256'],'bytes':item['logicalBytes']} for item in extraction['files']]}
    configpath=work/'config.json';img.write_json(configpath,config)
    generated_manifest=work/'stock-models.json';img.write_json(generated_manifest,stock)
    binary=OUT/'stock-img-manifest-tests'
    build=subprocess.run(['xcrun','swiftc','-Onone','-parse-as-library','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',
                          str(ROOT/'ios/App/NativeSAMPStockModels.swift'),str(ROOT/'tests/stock_img/manifest.swift'),'-o',str(binary)],capture_output=True,text=True,timeout=90)
    (OUT/'swift-build.log').write_text(build.stdout+build.stderr)
    if build.returncode:raise RuntimeError(build.stdout+build.stderr)
    owner_manifest=ROOT/'local-only/research/stock-img/stock-models.json'
    native=subprocess.run([str(binary),str(generated_manifest),str(owner_manifest) if owner_manifest.exists() else '-'],capture_output=True,text=True,timeout=30)
    if native.returncode:raise RuntimeError(native.stdout+native.stderr)
    manifest_result=json.loads(native.stdout)
    run=subprocess.run(['node',str(ROOT/'tests/stock_img/main.js'),str(configpath)],capture_output=True,text=True,timeout=90)
    (OUT/'stdout.log').write_text(run.stdout);(OUT/'stderr.log').write_text(run.stderr)
    if run.returncode:raise RuntimeError(run.stdout+run.stderr)
    result=json.loads(run.stdout);result['generatorChecks']=checks;result['nativeManifest']=manifest_result
    result['sourceSHA256']={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ['tools/assets/prepare_native_stock_img.py','stock_img_assets.js','tests/resources/test_stock_img_assets.py','tests/stock_img/main.js','tests/stock_img/manifest.swift']}
    img.write_json(OUT/'report.json',result);print(json.dumps(result,indent=2,sort_keys=True))
