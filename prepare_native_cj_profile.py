#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Stage only an explicitly selected fixed-Normal player body, never an archive.

Original/derived bytes, descriptors, checksums and receipts stay in local-only.
Native CJ format/rig/texture/GPU admission still belongs to the actual app.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import tempfile
import zlib

ROOT = Path(__file__).resolve().parent
NAME = 'cj-normal-vest-denim-v1'
PREFIX = 'game/native/' + NAME + '/'
FILES = {'template':'player.dff', 'part:torso':'vest.dff', 'part:head':'head.dff',
         'part:hands':'hands.dff', 'part:legs':'jeans.dff', 'part:feet':'sneaker.dff',
         'dictionary:player_torso':'player_torso.txd', 'dictionary:vest':'vest.txd',
         'dictionary:player_face':'player_face.txd', 'dictionary:jeansdenim':'jeansdenim.txd',
         'dictionary:sneakerbincblk':'sneakerbincblk.txd', 'rules':'clothes.dat'}
PARTS = {'torso':'vest','head':'head','hands':'hands','legs':'jeans','feet':'sneaker'}
RECIPES = [{'output':'torso','base':['player_torso','torso'],'cuts':[['vest','vest']]},
           {'output':'head','base':['player_face','face'],'cuts':[]},
           {'output':'legs','base':['jeansdenim','legs'],'cuts':[]},
           {'output':'feet','base':['sneakerbincblk','sneakerbincblk'],'cuts':[]}]


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':')).encode()


def private_directory(local, relative):
    local = Path(local).absolute()
    if local.is_symlink() or not local.is_dir():
        raise ValueError('Choose a regular private local-only directory')
    result = local
    for name in Path(relative).parts:
        if name in ('', '.', '..'):
            raise ValueError('Unsafe private output component')
        result = result / name
        if result.is_symlink() or result.exists() and not result.is_dir():
            raise ValueError('Private output directories must not be links or files')
    return result


def descriptor_for(rows):
    hashes = {}
    for row in rows:
        role = row['role']
        key = 'part:'+role[5:]+':'+PARTS[role[5:]] if role.startswith('part:') else role
        hashes[key] = row['sha256']
    hashes['recipe-v1'] = hashlib.sha256(canonical(RECIPES)).hexdigest()
    return {'schema':1, 'profile':NAME, 'variant':'Normal', 'legacyID':0, 'nativeID':0,
            'model':'null', 'animationStyleModel':'null', 'files':rows,
            'contentIdentity':hashlib.sha256(canonical(hashes)).hexdigest()}


def candidates(local):
    """Only this optional, complete declared overlay enters the prepared graph."""
    optional = Path(local)/('resources-v1/generated/'+NAME)
    if not optional.exists() and not optional.is_symlink():
        return {}
    directory = private_directory(local, 'resources-v1/generated/'+NAME)
    profile = directory / 'profile.json'
    if not directory.exists():
        return {}
    if profile.is_symlink() or not profile.is_file() or not 0 < profile.stat().st_size <= 65536:
        raise ValueError('Incomplete fixed Normal CJ descriptor')
    data = json.loads(profile.read_bytes())
    rows = data.get('files')
    if not isinstance(rows,list) or len(rows) != len(FILES) or not all(isinstance(row,dict) for row in rows):
        raise ValueError('Incomplete fixed Normal CJ file graph')
    if data != descriptor_for(rows):
        raise ValueError('Invalid fixed Normal CJ identity')
    result = {PREFIX+'profile.json':profile}
    seen = set()
    for row in rows:
        role = row.get('role'); name = FILES.get(role)
        if not name or role in seen or row.get('path') != PREFIX+name:
            raise ValueError('Invalid fixed Normal CJ role/path')
        seen.add(role)
        count = row.get('bytes'); digest = row.get('sha256'); crc = row.get('crc32')
        if (type(count) is not int or not 12 <= count <= 4*1024*1024 or
            not isinstance(digest,str) or len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest) or
            type(crc) is not int or not 0 <= crc <= 0xffffffff):
            raise ValueError('Invalid fixed Normal CJ file metadata')
        file = directory/name
        if file.is_symlink() or not file.is_file() or file.stat().st_size != count:
            raise ValueError('Missing fixed Normal CJ resource: '+name)
        result[PREFIX+name] = file
    if seen != set(FILES) or sum(row['bytes'] for row in rows) > 32*1024*1024:
        raise ValueError('Invalid fixed Normal CJ graph budget')
    return result


def prepare(local, pieces, clothes):
    output = private_directory(local, 'resources-v1/generated/'+NAME)
    output.parent.mkdir(parents=True,exist_ok=True)
    if output.exists():
        raise ValueError('Choose a fresh fixed CJ overlay; existing data is preserved')
    receipt_path = output.parent/(NAME+'-receipt.json')
    if receipt_path.exists() or receipt_path.is_symlink():
        raise ValueError('Existing CJ provenance must be preserved')
    stage = Path(tempfile.mkdtemp(prefix='.cj-partial-',dir=output.parent))
    rows, provenance = [], []
    try:
        for role,name in FILES.items():
            source = Path(clothes) if role == 'rules' else Path(pieces)/name
            if source.is_symlink() or not source.is_file():
                raise ValueError('A selected regular source file is required: '+name)
            before = source.stat()
            maximum = 65536 if role == 'template' else 256*1024 if role == 'rules' else 4*1024*1024
            if not 12 <= before.st_size <= maximum:
                raise ValueError('Selected CJ resource exceeds its bound: '+name)
            data = source.read_bytes()
            after = source.stat()
            stamp = lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
            if len(data) != before.st_size or stamp(before) != stamp(after):
                raise ValueError('Selected CJ source changed: '+name)
            (stage/name).write_bytes(data)
            row = {'role':role,'path':PREFIX+name,'bytes':len(data),
                   'sha256':hashlib.sha256(data).hexdigest(),'crc32':zlib.crc32(data)}
            rows.append(row); provenance.append({'source':str(source.absolute()),**row})
        descriptor = descriptor_for(rows)
        (stage/'profile.json').write_bytes(canonical(descriptor)+b'\n')
        os.rename(stage,output)
        indexed = candidates(local)
        receipt = {'schema':1,'profile':NAME,'output':str(output), 'sources':provenance,
                   'files':{name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
                            for name,p in indexed.items()},
                   'copiedAssetBytes':sum(row['bytes']for row in rows),
                   'contentIdentity':descriptor['contentIdentity']}
        with receipt_path.open('xb') as receipt_output:
            receipt_output.write(canonical(receipt)+b'\n')
        return receipt
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-only',type=Path,default=ROOT/'local-only')
    parser.add_argument('--pieces',type=Path,required=True,help='Explicit owned selected component/template/TXD directory')
    parser.add_argument('--clothes',type=Path,required=True,help='Explicit owned clothes.dat')
    args = parser.parse_args()
    result = prepare(args.local_only,args.pieces,args.clothes)
    print(json.dumps({'profile':NAME,'files':len(result['files']),'copiedAssetBytes':result['copiedAssetBytes'],
                      'output':result['output'],'contentIdentity':result['contentIdentity']},indent=2))


if __name__ == '__main__':
    main()
