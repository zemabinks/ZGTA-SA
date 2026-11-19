#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Generate exact owner-local IDE/raw-asset lookup metadata, without conversion.

Inputs are an owned data tree and a read-only raw DFF/TXD directory. Outputs must
stay under local-only; original IDE text/assets are never embedded in source.
Only active IDE directives from default.dat/gta.dat are loaded, unless an explicit
extra IDE is provided (for an independently supplied SA-MP supplemental pack).
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import binascii
import hashlib
import json
import pathlib
import re

SECTIONS={'objs':'object','tobj':'timed','anim':'animated','cars':'vehicle','peds':'ped','weap':'weapon','hier':'hierarchy'}
NAME=re.compile(r'[A-Za-z0-9_#+.()\-]{1,128}\Z')


def name(value):
    if not NAME.fullmatch(value) or value in ('.','..') or '..' in value:
        raise ValueError('Invalid model/dictionary name')
    return value.lower()


def generate(game_root,asset_root,url_prefix='game',extra_ides=()):
    game_root=pathlib.Path(game_root).resolve();asset_root=pathlib.Path(asset_root).resolve()
    if not game_root.is_dir() or not asset_root.is_dir():raise ValueError('Missing owned data/raw asset root')
    if url_prefix:
        if any(not NAME.fullmatch(part) or part in ('.','..') for part in url_prefix.split('/')):raise ValueError('Invalid URL prefix')
    paths={}
    for path in game_root.rglob('*'):
        if path.is_file() and not path.is_symlink():
            key=path.relative_to(game_root).as_posix().lower()
            if key in paths:raise ValueError('Ambiguous case-folded data path')
            paths[key]=path
    sources=[]
    def read(path):
        data=path.read_bytes()
        if len(data)>2*1024*1024:raise ValueError('IDE/config byte limit')
        sources.append({'path':path.relative_to(game_root).as_posix(),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
        return data.decode('latin1')
    active=[]
    for config in ('data/default.dat','data/gta.dat'):
        if config not in paths:raise ValueError('Missing explicit game config '+config)
        for line in read(paths[config]).splitlines():
            line=line.split('#',1)[0].strip()
            if not line:continue
            parts=line.split(None,1)
            if parts[0].upper()=='IDE':
                key=parts[1].strip().replace('\\','/').lower()
                if key not in paths:raise ValueError('Missing explicitly loaded IDE '+key)
                if key not in active:active.append(key)
    for value in extra_ides:
        key=str(value).replace('\\','/').lower()
        if key not in paths:raise ValueError('Missing supplemental IDE '+key)
        if key not in active:active.append(key)
    if len(active)>256:raise ValueError('IDE file limit')
    models={};parents={};parent_sources={};ignored={}
    for key in active:
        section=None
        for line_number,line in enumerate(read(paths[key]).splitlines(),1):
            # '#' begins comments in IDE files; names themselves cannot contain it.
            line=line.split('#',1)[0].strip()
            if not line:continue
            if ',' not in line and len(line.split())==1:
                section=None if line.lower()=='end' else line.lower();continue
            # Original loaders treat commas and whitespace as separators; three
            # retail vehicle rows omit a comma between model and dictionary.
            fields=re.split(r'[\s,]+',line)
            if section=='txdp':
                if len(fields)!=2:raise ValueError('Invalid TXD parent row')
                child,parent=map(name,fields)
                if child in parents and parents[child]!=parent:raise ValueError('Conflicting explicit TXD parent')
                parents[child]=parent;parent_sources[child]='ide'
            elif section in SECTIONS:
                if len(fields)<3:raise ValueError('Incomplete model row')
                model_id=int(fields[0]);model=name(fields[1]);dictionary=name(fields[2])
                if not 0<=model_id<=19999:raise ValueError('Stock model ID outside published namespace')
                entry={'id':model_id,'kind':SECTIONS[section],'model':model,'txd':dictionary,'source':key,'line':line_number}
                if model_id in models:raise ValueError('Duplicate model ID '+str(model_id))
                models[model_id]=entry
            else:ignored[section or 'none']=ignored.get(section or 'none',0)+1
    if len(models)>30000:raise ValueError('Model count limit')
    # Supporting engine reference: CFileLoader::LoadVehicleObject assigns the
    # vehicle TXD parent; CVehicleModelInfo::FindTextureCB checks generic first.
    # No reconstruction code is copied; the relation is kept explicit in metadata.
    for row in models.values():
        if row['kind']=='vehicle' and row['txd']!='vehicle':
            if row['txd'] not in parents:
                parents[row['txd']]='vehicle';parent_sources[row['txd']]='engine-vehicle-parent'
    def chain(dictionary):
        result=[]
        while dictionary:
            if dictionary in result or len(result)>=32:raise ValueError('TXD parent cycle/depth')
            result.append(dictionary);dictionary=parents.get(dictionary)
        return result
    for child in parents:chain(child)
    candidates={}
    for path in asset_root.rglob('*'):
        if path.is_file() and not path.is_symlink() and path.suffix.lower() in ('.dff','.txd'):
            key=path.name.lower()
            if key in candidates:raise ValueError('Ambiguous raw asset basename '+key)
            candidates[key]=path
            if len(candidates)>50000:raise ValueError('Raw asset count limit')
    assets={};rejected=[]
    for key,path in sorted(candidates.items()):
        relative=path.relative_to(asset_root).as_posix()
        if any(not NAME.fullmatch(p) or p in ('.','..') for p in relative.split('/')):raise ValueError('Invalid raw asset path')
        before=path.stat()
        if not 12<=before.st_size<=64*1024*1024:
            rejected.append({'file':relative,'reason':'file-size limit'});continue
        data=path.read_bytes();after=path.stat()
        if before.st_size!=after.st_size or before.st_mtime_ns!=after.st_mtime_ns:raise ValueError('Raw asset changed while hashing')
        expected=16 if key.endswith('.dff') else 22
        if int.from_bytes(data[:4],'little')!=expected:
            rejected.append({'file':relative,'reason':'unexpected RW root'});continue
        assets[key]={'path':('/'.join([url_prefix,relative]) if url_prefix else relative),'bytes':len(data),
                     'crc32':binascii.crc32(data)&0xffffffff,'sha256':hashlib.sha256(data).hexdigest()}
    rows=sorted(models.values(),key=lambda r:r['id'])
    available=[r for r in rows if r['model']+'.dff' in assets]
    complete=[r for r in available if all(t+'.txd' in assets for t in chain(r['txd']))]
    manifest={'schema':1,'models':rows,'parents':parents,'parentOrigins':parent_sources,'assets':assets,
              'vehicleDictionary':'vehicle','vehicleGenericFirst':True,'sources':sources}
    report={'models':len(rows),'activeIDEs':len(active),'rawDFFs':sum(k.endswith('.dff')for k in assets),
            'rawTXDs':sum(k.endswith('.txd')for k in assets),'modelsWithRawDFF':len(available),'modelsWithAllTXDs':len(complete),
            'kinds':{kind:sum(r['kind']==kind for r in rows)for kind in SECTIONS.values()},
            'availabilityByKind':{kind:sum(r['kind']==kind for r in available)for kind in SECTIONS.values()},
            'missingCommonIDs':[i for i in [966,980,1225,1231,19379,19353,19480] if i not in models or models[i]['model']+'.dff' not in assets],
            'rejectedRawFiles':rejected,'ignoredSections':ignored,
            'scope':'Exact owner-local metadata/file availability only; not native import/render or retail visual parity'}
    return manifest,report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-root',type=pathlib.Path,required=True)
    parser.add_argument('--asset-root',type=pathlib.Path,required=True)
    parser.add_argument('--url-prefix',default='game')
    parser.add_argument('--extra-ide',action='append',default=[])
    parser.add_argument('--output',type=pathlib.Path,required=True)
    args=parser.parse_args()
    output=args.output.resolve()
    if 'local-only' not in output.parts:parser.error('Generated owner metadata must remain under local-only')
    manifest,report=generate(args.game_root,args.asset_root,args.url_prefix,args.extra_ide)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(manifest,separators=(',',':'))+'\n')
    output.with_suffix('.report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':main()
