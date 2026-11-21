#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Read inert occupant tables from the supported owner-local browser archive.

Never executes the archive. Generated tables contain original data and stay
local. This does not provide population AI or establish retail PC behavior.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,stat,tempfile

ROOT=Path(__file__).resolve().parents[2]
SUPPORTED_SHA256='65ced5ef7706b4d682e7bbb6ae197eeecf6a38137a30f275189e471693ca0d2d'
MAX_BYTES=4_194_304
class TableError(ValueError):pass

def parse_tables(text):
    """Selected literal grammar only; no JavaScript evaluation or imports."""
    def one(pattern):
        matches=re.findall(pattern,text)
        if len(matches)!=1:raise TableError('Missing or ambiguous selected literal')
        return matches[0]
    array=r'\[\s*\d+(?:\s*,\s*\d+)*\s*\]'
    fallback=json.loads(one(r'(?<![\w$])xs\s*=\s*('+array+r')\s*[,;]'))
    hidden=json.loads(one(r'(?<![\w$])bz\s*=\s*new Set\(('+array+r')\)'))
    mapping=one(r'(?<![\w$])xc\s*=\s*\{(\s*\d+\s*:\s*\d+(?:\s*,\s*\d+\s*:\s*\d+)*\s*)\}')
    overrides={}
    for pair in mapping.split(','):
        key,value=map(int,pair.split(':'))
        if key in overrides or not 0<=key<=65535:raise TableError('Duplicate/invalid override model')
        overrides[key]=value
    if not 1<=len(fallback)<=512 or len(overrides)>512 or len(hidden)>512:
        raise TableError('Table count budget')
    if any(not 0<=skin<=65535 for skin in [*fallback,*overrides.values()]):raise TableError('Skin range')
    if len(set(hidden))!=len(hidden) or any(not 0<=model<=65535 for model in hidden):raise TableError('Hidden model range/identity')
    return dict(schema=1,fallback=fallback,overrides={str(k):v for k,v in overrides.items()},hiddenModels=hidden)

def convert(path):
    descriptor=os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0))
    with os.fdopen(descriptor,'rb')as stream:
        before=os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode)or not 0<before.st_size<=MAX_BYTES:raise TableError('Original regular-file byte budget')
        data=stream.read(MAX_BYTES+1);after=os.fstat(stream.fileno())
        if len(data)!=before.st_size or (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns):
            raise TableError('Original source changed during read')
    digest=hashlib.sha256(data).hexdigest()
    if digest!=SUPPORTED_SHA256:raise TableError('Unsupported archive profile; establish its bindings before conversion')
    catalog=parse_tables(data.decode('utf-8'))
    catalog.update(profile='zgta-browser-traffic-occupants-v1',sourceSHA256=digest)
    return catalog

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client-chunk',required=True,type=Path)
    parser.add_argument('--out',type=Path,default=ROOT/'local-only/traffic/game/native/traffic-occupants.json')
    args=parser.parse_args();out=args.out.resolve()
    if out.is_relative_to(ROOT)and not out.is_relative_to(ROOT/'local-only'):parser.error('Original tables inside the repository must stay under local-only/')
    if out.exists():parser.error('Output exists; choose a new private path')
    catalog=convert(args.client_chunk);data=(json.dumps(catalog,indent=2)+'\n').encode()
    out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=out.parent,prefix=out.name+'.',suffix='.partial',delete=False)as stream:
        temporary=Path(stream.name);stream.write(data)
    try:os.replace(temporary,out)
    finally:
        if temporary.exists():temporary.unlink()
    report=dict(status='CONVERTED_NOT_PLAYABLE',bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),
        sourceSHA256=catalog['sourceSHA256'],fallbackCount=len(catalog['fallback']),overrideCount=len(catalog['overrides']),
        hiddenModelCount=len(catalog['hiddenModels']),scope='Inert original table conversion; no AI, models, animation, rendering, server or retail acceptance')
    out.with_suffix('.report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
