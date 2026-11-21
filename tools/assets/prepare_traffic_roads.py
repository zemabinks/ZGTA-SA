#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Convert owner-local original exterior vehicle paths to compact SDRDv1.

Output is original game data and stays local. This does not implement route
selection, signals, vehicle population, traffic AI or a playable installation.
"""
from pathlib import Path
import argparse,hashlib,json,os,struct,sys,tempfile,zlib
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tools.assets import prepare_pedestrian_paths as pedestrian
PathFormatError=pedestrian.PathFormatError

def decode_area(data,area):
    # Reuse complete native-area identity/section validation and secure file
    # admission. Vehicle navigation has additional, separate cross-area refs.
    nodes=pedestrian.decode_area(data,area)
    total,vehicles,_,navis,links=struct.unpack_from('<5I',data)
    navigation=20+total*28;addresses=navigation+navis*14
    packed=addresses+(links+(192 if links else 0))*4
    decoded=[]
    for index in range(vehicles):
        node=dict(nodes[index]);first=struct.unpack_from('<H',data,20+index*28+16)[0]
        node['navigation']=[struct.unpack_from('<H',data,packed+(first+i)*2)[0]for i in range(len(node['targets']))]
        decoded.append(node)
    nav=[]
    for index in range(navis):
        at=navigation+index*14
        nav.append(dict(area=area,index=index,xy=struct.unpack_from('<2h',data,at),
            target=struct.unpack_from('<2H',data,at+4),direction=struct.unpack_from('<2b',data,at+8),
            flags=struct.unpack_from('<I',data,at+10)[0]))
    return dict(nodes=decoded,navigation=nav)

def encode_graph(areas,profile='roads'):
    if set(areas)!=set(range(64)):raise PathFormatError('All64 exterior areas are required')
    if profile not in ['roads','all-vehicle-paths']:raise PathFormatError('Unknown vehicle path profile')
    original_nodes=[node for area in range(64)for node in areas[area]['nodes']]
    # The original CPathNode byte0 bit7 denotes a water node. Compact road
    # traffic excludes those nodes; callers preparing boat navigation can
    # explicitly retain every original vehicle path in a separate graph.
    nodes=[node for node in original_nodes if profile=='all-vehicle-paths' or not node['flags']&128]
    selected={(node['area'],node['index'])for node in nodes}
    nav=[row for area in range(64)for row in areas[area]['navigation']if profile=='all-vehicle-paths' or tuple(row['target'])in selected]
    if not 0<len(nodes)<=65535 or not 0<len(nav)<=65535:raise PathFormatError('Compact vehicle/navigation identity budget')
    identities={(n['area'],n['index']):i for i,n in enumerate(nodes)}
    navigation={(n['area'],n['index']):i for i,n in enumerate(nav)}
    if len(identities)!=len(nodes)or len(navigation)!=len(nav):raise PathFormatError('Duplicate vehicle/navigation identity')
    offsets=[0];targets=[];navis=[];rebound={};rebound_links=0
    for node in nodes:
        if len(node['targets'])!=len(node['navigation']):raise PathFormatError('Vehicle/navigation adjacency differs')
        for (area,index,_),packed in zip(node['targets'],node['navigation']):
            if (area,index)not in identities:raise PathFormatError('Unresolved or nonvehicle target')
            key=(packed>>10,packed&1023)
            if key not in navigation:raise PathFormatError('Unresolved vehicle navigation')
            source_id=identities[node['area'],node['index']];target_id=identities[area,index]
            navi_id=navigation[key];reference=nav[navi_id]
            # Original areas can reuse one navigation row on stacked roads.
            # A compact row has one explicit attachment, so a row attached to
            # neither endpoint needs a separate edge-local binding. Preserve
            # its geometry/flags and use its signed direction to identify the
            # endpoint; never silently flip the lane or guess a zero dot.
            if tuple(reference['target'])not in [(node['area'],node['index']),(area,index)]:
                target_node=nodes[target_id]
                delta=[target_node['xyz'][i]-node['xyz'][i]for i in range(2)]
                dot=sum(a*b for a,b in zip(delta,reference['direction']))
                if dot==0:raise PathFormatError('Navigation direction cannot resolve edge-local attachment')
                attached_id=target_id if dot>0 else source_id
                binding=(navi_id,attached_id)
                if binding not in rebound:
                    attached_node=nodes[attached_id];rebound[binding]=len(nav)
                    nav.append({**reference,'target':(attached_node['area'],attached_node['index'])})
                navi_id=rebound[binding];rebound_links+=1
            targets.append(target_id);navis.append(navi_id)
        offsets.append(len(targets))
    if not 0<len(targets)<=65535 or len(nav)>65535:raise PathFormatError('Compact directed-link/navigation identity budget')
    attached=[]
    for row in nav:
        if tuple(row['target'])not in identities:raise PathFormatError('Navigation target is not a loaded vehicle node')
        attached.append(identities[tuple(row['target'])])
    result=bytearray(struct.pack('<8I',0x44524453,1,len(nodes),len(targets),len(nav),0,0,0))
    def section(values,code):
        values=list(values)
        if values:result.extend(struct.pack('<'+str(len(values))+code,*values))
        result.extend(b'\0'*((-len(result))%4))
    section((v for row in nodes for v in row['xyz']),'h');section(offsets,'I')
    section((row['flags']for row in nodes),'I')
    section((0 for _ in nodes),'B') # No query meaning established for this byte.
    section(targets,'I');section(navis,'I')
    section((v for row in nav for v in row['xy']),'h');section(attached,'I')
    section((v for row in nav for v in row['direction']),'b');section((row['flags']for row in nav),'I')
    if len(result)>8*pedestrian.MAX_BYTES:raise PathFormatError('Compact traffic graph byte budget')
    return bytes(result),dict(nodes=len(nodes),links=len(targets),navigation=len(nav),areas=64,profile=profile,
        excludedWaterNodes=len(original_nodes)-len(nodes),
        edgeLocalNavigationBindings=len(rebound),edgeLocalNavigationLinks=rebound_links,
        ignoredNodeBytes='zero; no source-decoder query use established')

def convert(root,receipt_path=None,profile='roads'):
    root=Path(root).resolve(strict=True)
    if not root.is_dir():raise PathFormatError('Original root must be a directory')
    receipt_bytes=None;catalogue={}
    if receipt_path:
        receipt_path=Path(receipt_path)
        if receipt_path.stat().st_size>pedestrian.MAX_BYTES:raise PathFormatError('Receipt byte budget')
        receipt_bytes=receipt_path.read_bytes();receipt=json.loads(receipt_bytes)
        if receipt.get('schema')!=1 or receipt.get('profile')!='zgta-raw-resources-v1':raise PathFormatError('Original receipt profile')
        for row in receipt['resources']:
            name=row['path'].lower()
            if name in catalogue:raise PathFormatError('Ambiguous receipt member')
            catalogue[name]=row
    areas={};inputs=[];total_bytes=0;total_nodes=0;total_links=0
    for area in range(64):
        name=f'data/paths/nodes{area}.dat';path=pedestrian.member(root,name);data=pedestrian.read_regular(path)
        digest=hashlib.sha256(data).hexdigest();header=struct.unpack_from('<5I',data)
        total_bytes+=len(data);total_nodes+=header[0];total_links+=header[4]
        if total_bytes>8*pedestrian.MAX_BYTES or total_nodes>150000 or total_links>300000:raise PathFormatError('Original aggregate budget')
        if receipt_bytes:
            row=catalogue.get(name)
            if not row or row['bytes']!=len(data)or row['sha256']!=digest:raise PathFormatError('Original receipt member mismatch')
        areas[area]=decode_area(data,area);inputs.append(dict(path=str(path),bytes=len(data),sha256=digest))
    data,report=encode_graph(areas,profile)
    if any(hashlib.sha256(pedestrian.read_regular(Path(row['path']))).hexdigest()!=row['sha256']for row in inputs):raise PathFormatError('Original inputs changed before publication')
    if receipt_path and receipt_path.read_bytes()!=receipt_bytes:raise PathFormatError('Original receipt changed before publication')
    report.update(bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),crc32=f'{zlib.crc32(data)&0xffffffff:08x}',
        sourceFiles=inputs,originalReceiptVerified=receipt_bytes is not None,
        scope='Original exterior vehicle graph conversion only; not traffic policy, playable native/browser integration or retail behavior')
    return data,report

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--raw-root',required=True,type=Path)
    parser.add_argument('--receipt',type=Path);parser.add_argument('--out',type=Path,default=ROOT/'local-only/traffic/game/world/roads.bin')
    parser.add_argument('--profile',choices=['roads','all-vehicle-paths'],default='roads')
    parser.add_argument('--replace',action='store_true');args=parser.parse_args();out=args.out.resolve()
    if out.is_relative_to(ROOT)and not out.is_relative_to(ROOT/'local-only'):parser.error('Derived original data must stay under local-only/')
    if out.exists()and not args.replace:parser.error('Output exists; choose a new private path or explicitly --replace')
    sources=[Path(__file__).resolve(),Path(pedestrian.__file__).resolve()]
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in sources}
    data,report=convert(args.raw_root,args.receipt,args.profile)
    if any(hashlib.sha256(Path(p).read_bytes()).hexdigest()!=digest for p,digest in hashes.items()):raise PathFormatError('Converter source changed')
    report['converterSources']=hashes;out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=out.name+'.',suffix='.partial',dir=out.parent,delete=False)as stream:
        temporary=Path(stream.name);stream.write(data)
    try:os.replace(temporary,out)
    finally:
        if temporary.exists():temporary.unlink()
    out.with_suffix('.report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items()if k!='sourceFiles'},indent=2))
if __name__=='__main__':main()
