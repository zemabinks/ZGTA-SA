#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Enable owner-local civilian population from original IDE and prepared data.

Writes local server configuration, not original zone/time density or full AI.
Original resources and derived configuration must stay outside public source.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,struct,tempfile,zlib
ROOT=Path(__file__).resolve().parents[2]
def read(path,maximum):
    path=Path(path)
    if not path.is_file()or path.stat().st_size>maximum:raise ValueError('Missing or oversized population input: '+str(path))
    data=path.read_bytes()
    if len(data)>maximum:raise ValueError('Population input changed size')
    return data
def prepare(ide,index,graph,models):
    graph=bytes(graph)
    if len(graph)<32 or len(graph)>3*1048576 or struct.unpack_from('<2I',graph)!=(0x44504453,1):raise ValueError('Expected prepared SDPDv1 graph')
    nodes,links=struct.unpack_from('<2I',graph,8)
    if not 0<nodes<=65535 or links>300000:raise ValueError('Population graph counts')
    cursor=32
    def section(count,size):
        nonlocal cursor
        start=cursor;cursor=(cursor+count*size+3)&~3
        if cursor>len(graph):raise ValueError('Population graph section range')
        return start
    section(nodes*3,2);first=section(nodes+1,4);section(nodes,1);section(nodes,1)
    target=section(links,2);section(links,1)
    if cursor!=len(graph):raise ValueError('Population graph exact end')
    offsets=struct.unpack_from('<'+str(nodes+1)+'I',graph,first)
    if offsets[0]!=0 or offsets[-1]!=links or any(not 0<=b-a<=15 for a,b in zip(offsets,offsets[1:])):raise ValueError('Population graph adjacency')
    if any(value>=nodes for value in struct.unpack_from('<'+str(links)+'H',graph,target)):raise ValueError('Population graph target')
    ids={};names=set()
    for line in ide.decode('ascii').splitlines():
        text=line.split('#',1)[0].strip()
        if not text or not text[0].isdigit():continue
        row=[part.strip()for part in text.split(',')]
        if len(row)<5:raise ValueError('Malformed original pedestrian definition')
        number=int(row[0]);name=row[1].lower()
        if number in ids or name in names:raise ValueError('Duplicate original pedestrian identity')
        names.add(name);ids[number]=(name,row[3].upper())
    native=json.loads(index)
    if not isinstance(native.get('peds'),dict):raise ValueError('Expected prepared model index')
    selected=[];unavailable=[]
    for key,name in native['peds'].items():
        if not re.fullmatch(r'\d{1,3}',key)or not isinstance(name,str)or not re.fullmatch(r'[a-zA-Z0-9_]{1,32}',name):continue
        identity=int(key);original=ids.get(identity)
        if not original or original[0]!=name.lower()or original[1]not in ['CIVMALE','CIVFEMALE']:continue
        if all((models/(name+suffix)).is_file()for suffix in ['.bin','.png','.skel.bin']):selected.append(identity)
        else:unavailable.append(identity)
    if not selected:raise ValueError('No matching original civilian models have prepared mesh/texture/skeleton files')
    return dict(version=1,profile='zgta-original-pavement-population-v1',pathsCRC32=f'{zlib.crc32(graph)&0xffffffff:08x}',
        models=sorted(selected),maximum=64,perObserver=12),dict(availableCivilianModels=len(selected),unavailable=sorted(unavailable),
        scope='Original IDE identities with available prepared civilian models and graph CRC. Independent walking/flee/injury tasks. Original population groups, zones, time densities, social AI, traffic and police remain incomplete.')
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--peds-ide',required=True,type=Path)
    parser.add_argument('--site',type=Path,default=ROOT/'local-only/site')
    parser.add_argument('--out',type=Path,default=ROOT/'local-only/selfhost/population.json')
    parser.add_argument('--replace',action='store_true')
    args=parser.parse_args();out=args.out.resolve()
    if out.is_relative_to(ROOT)and not out.is_relative_to(ROOT/'local-only'):parser.error('Derived population data must stay under local-only/')
    if out.exists()and not args.replace:parser.error('Existing population configuration; choose a new path or explicitly --replace')
    paths=[args.peds_ide,args.site/'game/native/models/index.json',args.site/'game/world/paths.bin']
    data=[read(path,maximum)for path,maximum in zip(paths,[1048576,1048576,3*1048576])]
    config,report=prepare(*data,args.site/'game/native/models')
    hashes={str(p.resolve()):hashlib.sha256(d).hexdigest()for p,d in zip(paths,data)}
    if any(hashlib.sha256(p.read_bytes()).hexdigest()!=hashes[str(p.resolve())]for p in paths):raise ValueError('Population sources changed')
    out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=out.name+'.',suffix='.partial',dir=out.parent,delete=False)as stream:
        temporary=Path(stream.name);stream.write((json.dumps(config,indent=2)+'\n').encode())
    try:os.replace(temporary,out)
    finally:
        if temporary.exists():temporary.unlink()
    report.update(sourceHashes=hashes,configurationSHA256=hashlib.sha256(out.read_bytes()).hexdigest())
    out.with_suffix('.report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
