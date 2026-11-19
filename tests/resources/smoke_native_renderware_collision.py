#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Bounded COL/COLL/COL2/COL3 and embedded collision regressions.

Own generated fixtures are distributable. Owner payloads, optional unmodified
GPL DragonFF reference reader/license, goldens and executables stay local-only.
No shared exporter is called and no original game resource is written.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import types

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'local-only/research/runtime-collision'


def pack(fmt,*args): return struct.pack('<'+fmt,*args)
def rw(kind,payload=b''): return pack('III',kind,len(payload),0x1803ffff)+payload


def fixture(version, groups=True, shadow=True):
    surface = bytes([4,7,8,0xab]); box_surface = bytes([9,10,11,0x12])
    lo,hi,center,radius = (-3.,-3.,-3.),(3.,3.,3.),(0.,0.,0.),5.
    if version == 1:
        body=pack('10f',radius,*center,*lo,*hi)
        body+=pack('I4f',1,.5,1,-2,3)+surface+pack('II',0,1)
        body+=pack('6f',-1,-1,-1,1,1,1)+box_surface
        body+=pack('I9f',3,0,0,0,1,0,0,0,1,0)+pack('I3I',1,0,1,2)+bytes([12,13,14,0x34])
    else:
        header_size=108 if version==2 else 120
        data=bytearray();offsets=[]
        def add(value):
            offsets.append(header_size+len(data)-4);data.extend(value)
        add(pack('4f',1,-2,3,.5)+surface)
        add(pack('6f',-1,-1,-1,1,1,1)+box_surface)
        offsets.append(0)
        add(pack('9h',0,0,0,128,0,0,0,128,0))
        if groups:
            data.extend(pack('6fHHI',-1,-1,-1,1,1,1,0,0,1))
        add(pack('3H2B',0,1,2,12,0x34));offsets.append(0)
        if version==3 and shadow:
            add(pack('9h',-256,0,0,0,-256,0,256,0,0))
            add(pack('3H2B',0,2,1,19,0x56))
        flags=2+(8 if groups else 0)+(16 if version==3 and shadow else 0)
        body=pack('10f',*lo,*hi,*center,radius)+pack('HHHBx7I',1,1,1,0,flags,*offsets[:6])
        if version==3:body+=pack('3I',1 if shadow else 0,*(offsets[6:] if shadow else [0,0]))
        body+=data
    header=pack('4sI22sH',b'COLL' if version==1 else ('COL'+str(version)).encode(),len(body)+24,b'generated',42)
    return header+body


def surface(material,flags,brightness,light):
    return dict(material=material,flags=flags,brightness=brightness,lighting=light,day=light&15,night=light>>4)


def golden(version,groups=True,shadow=True,legacy=False):
    bounds=dict(min=[-3.,-3.,-3.],max=[3.,3.,3.],center=[0.,0.,0.],radius=5.)
    main=dict(vertices=[[0.,0.,0.],[1.,0.,0.],[0.,1.,0.]],faces=[dict(indices=[0,1,2],surface=surface(12,13 if version==1 else None,14 if version==1 else None,0x34))])
    sh=dict(vertices=[[-2.,0.,0.],[0.,-2.,0.],[2.,0.,0.]],faces=[dict(indices=[0,2,1],surface=surface(19,None,None,0x56))])
    return dict(version=version,name=None if legacy else 'generated',id=None if legacy else 42,
        flags=None if version==1 else 2+(8 if groups else 0)+(16 if version==3 and shadow else 0),physical=True,bounds=bounds,
        spheres=[dict(center=[1.,-2.,3.],radius=.5,surface=surface(4,7,8,0xab))],
        boxes=[dict(min=[-1.,-1.,-1.],max=[1.,1.,1.],surface=surface(9,10,11,0x12))],mesh=main,
        groups=[dict(min=[-1.,-1.,-1.],max=[1.,1.,1.],first=0,last=0)] if version>1 and groups else [],
        shadow=sh if version==3 and shadow else None)


def load_oracle():
    path=OUT/'reference/DragonFF-col.py'
    if not path.exists():return None
    # Preserve the GPL module unchanged; satisfy only its simple name-length
    # dependency without importing Blender or any game/website source.
    package=types.ModuleType('zgtasa_collision_reference');package.__path__=[]
    dependency=types.ModuleType(package.__name__+'.dff')
    dependency.strlen=lambda value: value.find(b'\0') if b'\0' in value else len(value)
    sys.modules[package.__name__]=package;sys.modules[dependency.__name__]=dependency
    spec=importlib.util.spec_from_file_location(package.__name__+'.col',path)
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
    return module


def oracle_model(model,legacy=False):
    def surf(s):return surface(s.material,s.flags,s.brightness,s.light)
    def face(f):
        return dict(indices=[f.a,f.b,f.c],surface=surf(f.surface) if model.version==1 else surface(f.material,None,None,f.light))
    return dict(version=model.version,name=None if legacy else model.model_name,id=None if legacy else model.model_id,
        flags=None if model.version==1 else model.flags,
        physical=bool(model.spheres or model.boxes or model.mesh_faces),
        bounds=dict(min=list(model.bounds.min),max=list(model.bounds.max),center=list(model.bounds.center),radius=model.bounds.radius),
        spheres=[dict(center=list(s.center),radius=s.radius,surface=surf(s.surface))for s in model.spheres],
        boxes=[dict(min=list(b.min),max=list(b.max),surface=surf(b.surface))for b in model.boxes],
        mesh=dict(vertices=[list(v)for v in model.mesh_verts],faces=[face(f)for f in model.mesh_faces]),
        groups=[dict(min=list(g.min),max=list(g.max),first=g.start,last=g.end)for g in model.face_groups],
        shadow=dict(vertices=[list(v)for v in model.shadow_verts],faces=[face(f)for f in model.shadow_faces]) if model.shadow_faces else None)


def compare(a,b,where='model'):
    if isinstance(b,dict):
        assert set(a)==set(b),(where,set(a)^set(b))
        for k in b:compare(a[k],b[k],where+'.'+k)
    elif isinstance(b,list):
        assert len(a)==len(b),(where,len(a),len(b))
        for i,v in enumerate(b):compare(a[i],v,where+f'[{i}]')
    elif isinstance(b,float):assert math.isclose(a,b,rel_tol=1e-7,abs_tol=1e-7),(where,a,b)
    else:assert a==b,(where,a,b)


def main():
    OUT.mkdir(parents=True,exist_ok=True);fixtures=OUT/'fixtures';fixtures.mkdir(exist_ok=True)
    cases,expected,owner_hashes=[],[],{}
    def add(name,data,expect=None,mode=None,prefix=None,limit=None):
        path=fixtures/(name+'.bin');path.write_bytes(data)
        cases.append(dict(path=str(path),mode=mode,prefix=prefix,limit=limit));expected.append(expect)
        return path
    originals={v:fixture(v)for v in[1,2,3]}
    oracle=load_oracle()
    for v,data in originals.items():
        value=golden(v);add('col-'+str(v),data,dict(models=[value]))
        if oracle:
            ref=oracle.coll();ref.load_memory(data);compare([oracle_model(m)for m in ref.models],[value])
        for n in range(len(data)):add(f'prefix-{v}-{n:04}',data,None,prefix=n)
    add('explicit-headless-col1',originals[1][32:],dict(models=[golden(1,legacy=True)]),mode='legacy')
    add('unknown-headless-file',originals[1][32:])
    add('collection',b''.join(originals.values()),dict(models=[golden(v)for v in[1,2,3]]))
    pad=originals[3]+bytes((-len(originals[3]))%2048)
    add('sector-padding',pad,dict(models=[golden(3)]))
    add('sector-misaligned',pad+b'\0');add('sector-extra',pad+bytes(2048));add('sector-nonzero',pad[:-1]+b'\1')
    add('col4-unsupported',b'COL4'+originals[3][4:])
    def mutate(name,offset,fmt,*values,version=3):
        data=bytearray(originals[version]);struct.pack_into('<'+fmt,data,offset,*values);add(name,bytes(data))
    mutate('length-overflow',4,'I',0xffffffff)
    mutate('negative-radius',68,'f',-1)
    mutate('nan-bounds',32,'f',float('nan'));mutate('inf-bounds',32,'f',float('inf'))
    mutate('inverted-bounds',32,'f',100)
    mutate('sphere-count-overflow',72,'H',65535)
    mutate('line-unsupported',78,'B',1);mutate('planes-unsupported',104,'I',116)
    mutate('collision-flag-mismatch',80,'I',24)
    mutate('shadow-flag-mismatch',80,'I',10)
    mutate('sphere-offset-zero',84,'I',0);mutate('sphere-offset-header',84,'I',4)
    mutate('sphere-offset-overflow',84,'I',0xffffffff);mutate('box-overlap',88,'I',116)
    mutate('vertex-offset-overlap',96,'I',116);mutate('face-offset-overlap',100,'I',116)
    base=originals[3];sphere_at=struct.unpack_from('<I',base,84)[0]+4
    mutate('sphere-negative',sphere_at+12,'f',-1);mutate('sphere-nan',sphere_at,'f',float('nan'))
    faces_at=struct.unpack_from('<I',base,100)[0]+4
    mutate('vertex-index-overflow',faces_at,'H',65535)
    mutate('group-count-overflow',faces_at-4,'I',0xffffffff)
    mutate('group-face-range',faces_at-4-28+24,'HH',0,1)
    shadow_at=struct.unpack_from('<I',base,116)[0]+4
    mutate('shadow-index-overflow',shadow_at,'H',65535)
    mutate('shadow-offset-overlap',112,'I',116)
    mutate('shadow-offset-order',112,'I',struct.unpack_from('<I',base,116)[0]+6)
    mutate('legacy-sphere-count',72,'I',0xffffffff,version=1)
    mutate('legacy-lines',96,'I',1,version=1)
    mutate('legacy-vertex-index',176,'I',3,version=1)
    mutate('legacy-negative-sphere',76,'f',-1,version=1)
    for limit in['bytes','spheres','boxes','faces','vertices','groups','totalPrimitives','totalVertices']:
        add('limit-'+limit,base,limit=limit)
    add('limit-models',b''.join(originals.values()),limit='models')
    embedded=rw(16,rw(1,pack('3I',0,0,0))+rw(3,rw(0x253f2fa,base)))
    off=12+24+12+12
    add('embedded-col3',embedded,dict(embedded=[dict(offset=off,bytes=len(base),legacy=False,models=[golden(3)])]),mode='embedded')
    legacy=originals[1][32:];embedded_legacy=rw(16,rw(1,pack('3I',0,0,0))+rw(3,rw(0x253f2fa,legacy)))
    add('embedded-col1',embedded_legacy,dict(embedded=[dict(offset=off,bytes=len(legacy),legacy=True,models=[golden(1,legacy=True)])]),mode='embedded')
    add('no-collision-fallback',rw(16,rw(1,pack('3I',0,0,0))+rw(3)),dict(embedded=[]),mode='embedded')
    add('limit-chunks',embedded,mode='embedded',limit='chunks');add('limit-dff-bytes',embedded,mode='embedded',limit='dffBytes')
    add('malformed-plugin',embedded[:-1],mode='embedded')
    inventory=[]
    archive=ROOT/'local-only/site/game'
    if '--no-archive'not in sys.argv and archive.is_dir():
        for path in sorted(archive.glob('*.dff')):
            data=path.read_bytes();owner_hashes[str(path)]=hashlib.sha256(data).hexdigest()
            if len(data)<12:continue
            clump_end=12+struct.unpack_from('<I',data,4)[0];at=12;entries=[]
            while at+12<=clump_end:
                kind,size,_=struct.unpack_from('<III',data,at);start=at+12;end=start+size
                assert end<=clump_end
                if kind==3:
                    p=start
                    while p+12<=end:
                        k,n,_=struct.unpack_from('<III',data,p);a=p+12;b=a+n;assert b<=end
                        if k==0x253f2fa:
                            raw=data[a:b];headerless=not raw.startswith(b'COL')
                            inv=dict(file=path.name,offset=a,bytes=n,signature='headerless-COLL'if headerless else raw[:4].decode(),sha256=hashlib.sha256(raw).hexdigest())
                            inventory.append(inv)
                            if oracle:
                                ref=oracle.coll();ref.load_memory(raw)
                                assert len(ref.models)==1,'expected one source collision model'
                                values=[oracle_model(m,headerless)for m in ref.models]
                                entries.append(dict(offset=a,bytes=n,legacy=headerless,models=values))
                            else:entries=None
                        p=b
                    assert p==end
                at=end
            assert at==clump_end
            if oracle or entries==[]:
                cases.append(dict(path=str(path.resolve()),mode='embedded'));expected.append(dict(embedded=entries))
            else:
                # Without the optional primary oracle, still validate decoding,
                # while making that weaker coverage explicit in the report.
                cases.append(dict(path=str(path.resolve()),mode='embedded'));expected.append('accepted-only')
    manifest=OUT/'manifest.json';manifest.write_text(json.dumps(cases))
    compile_=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'module-cache'),
        str(ROOT/'ios/App/NativeRenderWareCollision.swift'),str(ROOT/'tests/resources/smoke_native_renderware_collision.swift'),
        '-o',str(OUT/'collision-tests')],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (OUT/'build.log').write_text(compile_.stdout);assert compile_.returncode==0,compile_.stdout
    run=subprocess.run([str(OUT/'collision-tests'),str(manifest),str(OUT/'results.json')],
        cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (OUT/'run.log').write_text(run.stdout);assert run.returncode==0,run.stdout
    results=json.loads((OUT/'results.json').read_text());failures=[]
    for case,actual,value in zip(cases,results,expected):
        try:
            assert actual['accepted']==(value is not None),actual.get('error','unexpected acceptance')
            if isinstance(value,dict):compare({k:v for k,v in actual.items()if k!='accepted'},value)
        except AssertionError as error:failures.append(dict(path=case['path'],prefix=case.get('prefix'),error=str(error)))
    for path,digest in owner_hashes.items():assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,'owner source modified'
    report=dict(cases=len(cases),accepted=sum(r['accepted']for r in results),rejected=sum(not r['accepted']for r in results),
        ownerDFFs=len(owner_hashes),embeddedPayloads=len(inventory),versions={v:sum(i['signature']==v for i in inventory)for v in sorted({i['signature']for i in inventory})},
        primaryOracleAvailable=oracle is not None,ownerSourcesUnchanged=True,failures=failures,
        sourceSHA256=hashlib.sha256((ROOT/'ios/App/NativeRenderWareCollision.swift').read_bytes()).hexdigest(),
        formatReference='https://github.com/Parik27/DragonFF/blob/master/gtaLib/col.py',
        referenceLicense='GPL-3.0-or-later; Copyright (C) 2019 Parik; private unmodified reference only',
        referenceSHA256=hashlib.sha256((OUT/'reference/DragonFF-col.py').read_bytes()).hexdigest()if oracle else None)
    totals=dict(spheres=0,boxes=0,mainVertices=0,mainFaces=0,faceGroups=0,shadowVertices=0,shadowFaces=0)
    if owner_hashes:
        for row in results[-len(owner_hashes):]:
            if not row['accepted']:continue
            for entry in row['embedded']:
                for model in entry['models']:
                    totals['spheres']+=len(model['spheres']);totals['boxes']+=len(model['boxes'])
                    totals['mainVertices']+=len(model['mesh']['vertices']);totals['mainFaces']+=len(model['mesh']['faces'])
                    totals['faceGroups']+=len(model['groups'])
                    if model['shadow']:
                        totals['shadowVertices']+=len(model['shadow']['vertices']);totals['shadowFaces']+=len(model['shadow']['faces'])
    report['actualOwnerTotals']=totals
    (OUT/'final-inventory.json').write_text(json.dumps(inventory,indent=2)+'\n')
    (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    assert not failures,'Collision regression failures'


if __name__=='__main__':main()
