#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Convert owner-local original PC pedestrian paths to the SDPD v1 graph.

The output contains original game data. Keep it local. This converter provides
graph compatibility, not population selection, NPC AI or original task parity.
"""
from pathlib import Path
import argparse, hashlib, json, os, re, stat, struct, tempfile, zlib

ROOT=Path(__file__).resolve().parents[2]
MAX_BYTES=1_048_576
class PathFormatError(ValueError): pass

def decode_area(data, area):
    if not isinstance(data,bytes) or not 0<=area<64 or not 20<=len(data)<=MAX_BYTES:
        raise PathFormatError('Original area/byte budget')
    total,vehicles,peds,navis,links=struct.unpack_from('<5I',data)
    if max(total,vehicles,peds,navis,links)>65535 or navis>1024 or total!=vehicles+peds:
        raise PathFormatError('Original header counts')
    reserve=192 if links else 0
    addresses=20+total*28+navis*14
    packed=addresses+(links+reserve)*4
    lengths=packed+links*2
    intersections=lengths+links+reserve
    if intersections+links+reserve!=len(data):raise PathFormatError('Original section lengths')
    nodes=[]
    for index in range(total):
        at=20+index*28
        first,file_area,file_index=struct.unpack_from('<3H',data,at+16)
        flags=struct.unpack_from('<I',data,at+24)[0];degree=flags&15
        if file_area!=area or file_index!=index or first+degree>links:
            raise PathFormatError('Original node identity/adjacency range')
        targets=[]
        for link in range(first,first+degree):
            target_area,target_node=struct.unpack_from('<2H',data,addresses+link*4)
            if target_area>=64:raise PathFormatError('Original target area')
            targets.append((target_area,target_node,data[intersections+link]))
        nodes.append(dict(area=area,index=index,ped=index>=vehicles,
            xyz=struct.unpack_from('<3h',data,at+8),width=data[at+22],flags=flags,targets=targets))
    return nodes

def encode_graph(areas):
    if set(areas)!=set(range(64)):raise PathFormatError('All64 original exterior areas are required')
    pedestrians=[node for area in range(64)for node in areas[area]if node['ped']]
    if not 0<len(pedestrians)<=65535:raise PathFormatError('Compact pedestrian ID budget')
    identities={(n['area'],n['index']):i for i,n in enumerate(pedestrians)}
    if len(identities)!=len(pedestrians):raise PathFormatError('Duplicate original node identity')
    offsets=[0];targets=[];kinds=[]
    for node in pedestrians:
        for area,index,kind in node['targets']:
            if (area,index)not in identities:raise PathFormatError('Unresolved or nonpedestrian path target')
            targets.append(identities[area,index]);kinds.append(kind)
        offsets.append(len(targets))
    if len(targets)>300000:raise PathFormatError('Compact link budget')
    result=bytearray(struct.pack('<8I',0x44504453,1,len(pedestrians),len(targets),0,0,0,0))
    def section(values,code):
        values=list(values)
        if values:result.extend(struct.pack('<'+str(len(values))+code,*values))
        result.extend(b'\0'*((-len(result))%4))
    section((coordinate for node in pedestrians for coordinate in node['xyz']),'h')
    section(offsets,'I')
    # The selected browser decoder does not consume this node byte. Preserve
    # original node flags in the input owner; do not invent a bit translation.
    section((0 for _ in pedestrians),'B')
    section((node['width']for node in pedestrians),'B')
    section(targets,'H');section(kinds,'B')
    if len(result)>3*MAX_BYTES:raise PathFormatError('Compact byte budget')
    return bytes(result),dict(nodes=len(pedestrians),links=len(targets),areas=64,
        ignoredNodeBytes='zero; no source-decoder semantic use established')

def member(root, relative):
    if not re.fullmatch(r'data/paths/nodes(?:[0-9]|[1-5][0-9]|6[0-3])\.dat',relative):
        raise PathFormatError('Unexpected original member')
    current=root
    for component in relative.split('/'):
        entries=list(current.iterdir())
        if len(entries)>10000:raise PathFormatError('Member directory budget')
        matches=[p for p in entries if p.name.lower()==component]
        if len(matches)!=1 or matches[0].is_symlink():raise PathFormatError('Missing, ambiguous or symbolic original member')
        current=matches[0]
    return current

def read_regular(path):
    descriptor=os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0))
    with os.fdopen(descriptor,'rb')as stream:
        before=os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode)or not 20<=before.st_size<=MAX_BYTES:raise PathFormatError('Original regular-file byte budget')
        data=stream.read(MAX_BYTES+1);after=os.fstat(stream.fileno())
        if (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns)or len(data)!=before.st_size:
            raise PathFormatError('Original file changed during read')
        return data

def convert(root, receipt_path=None):
    root=Path(root).resolve(strict=True)
    if not root.is_dir():raise PathFormatError('Original root must be a directory')
    if receipt_path and Path(receipt_path).stat().st_size>MAX_BYTES:raise PathFormatError('Original receipt byte budget')
    receipt_bytes=Path(receipt_path).read_bytes()if receipt_path else None
    catalogue={}
    if receipt_bytes:
        receipt=json.loads(receipt_bytes)
        if receipt.get('schema')!=1 or receipt.get('profile')!='zgta-raw-resources-v1':raise PathFormatError('Original resource receipt profile')
        for row in receipt['resources']:
            name=row['path'].lower()
            if name in catalogue:raise PathFormatError('Ambiguous receipt member')
            catalogue[name]=row
    areas={};inputs=[];total_bytes=0;total_nodes=0;total_links=0
    for area in range(64):
        name=f'data/paths/nodes{area}.dat';path=member(root,name);data=read_regular(path);digest=hashlib.sha256(data).hexdigest()
        total_bytes+=len(data);total_nodes+=struct.unpack_from('<I',data)[0];total_links+=struct.unpack_from('<I',data,16)[0]
        if total_bytes>8*MAX_BYTES or total_nodes>150000 or total_links>300000:raise PathFormatError('Original graph aggregate budget')
        if receipt_bytes:
            row=catalogue.get(name)
            if not row or row['bytes']!=len(data)or row['sha256']!=digest:raise PathFormatError('Original member does not match receipt')
        areas[area]=decode_area(data,area);inputs.append(dict(path=str(path),bytes=len(data),sha256=digest))
    output,summary=encode_graph(areas)
    if any(hashlib.sha256(read_regular(Path(row['path']))).hexdigest()!=row['sha256']for row in inputs):raise PathFormatError('Original source changed before publication')
    if receipt_path and Path(receipt_path).read_bytes()!=receipt_bytes:raise PathFormatError('Original receipt changed before publication')
    summary.update(bytes=len(output),sha256=hashlib.sha256(output).hexdigest(),crc32=f'{zlib.crc32(output)&0xffffffff:08x}',
        originalReceiptVerified=receipt_bytes is not None,sourceFiles=inputs,
        scope='Original pedestrian graph conversion only; no AI, spawning, traffic policy or retail runtime acceptance')
    return output,summary

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw-root',required=True,type=Path)
    parser.add_argument('--receipt',type=Path)
    parser.add_argument('--out',type=Path,default=ROOT/'local-only/population/game/world/paths.bin')
    parser.add_argument('--replace',action='store_true')
    args=parser.parse_args();out=args.out.resolve()
    if out.is_relative_to(ROOT)and not out.is_relative_to(ROOT/'local-only'):
        parser.error('Original graph outputs inside this repository must stay under local-only/')
    if out.exists()and not args.replace:parser.error('Output exists; choose a new private path or explicitly --replace')
    source_hash=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    data,report=convert(args.raw_root,args.receipt)
    if hashlib.sha256(Path(__file__).read_bytes()).hexdigest()!=source_hash:raise PathFormatError('Converter changed during execution')
    report['converterSHA256']=source_hash
    out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=out.name+'.',suffix='.partial',dir=out.parent,delete=False)as stream:
        temporary=Path(stream.name);stream.write(data)
    try:os.replace(temporary,out)
    finally:
        if temporary.exists():temporary.unlink()
    out.with_suffix('.report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items()if k!='sourceFiles'},indent=2))
if __name__=='__main__':main()
