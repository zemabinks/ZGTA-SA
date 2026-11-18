#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Asset-free authored parser, body assembly, texture and rule regressions."""
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,tempfile,sys
from smoke_native_renderware_skeleton import fixture
from smoke_native_renderware_dff import chunk,pack

ROOT=Path(__file__).resolve().parent
NAMES=['NativeRenderWareDFF','NativeRenderWareSkeleton','NativeRenderWareTXD',
       'NativeCJAssembly','NativeCJTextures','NativeCJClothesRules','NativeCJResources']
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def entries(data):
    at=0;result=[]
    while at<len(data):
        kind,size,stamp=struct.unpack_from('<III',data,at);end=at+12+size
        assert end<=len(data);result.append((kind,data[at+12:end]));at=end
    return result
def named_fixture(name):
    parts=entries(fixture()[12:]);out=[]
    for kind,body in parts:
        if kind==14:
            rows=entries(body);rows[1]=(3,rows[1][1]+chunk(0x253f2fe,name.encode()+b'\0'))
            body=b''.join(chunk(k,b)for k,b in rows)
        if kind==26:
            rows=entries(body);geometry=entries(rows[1][1]);raw=geometry[0][1]
            flags,uv,unused,triangles,vertices,morphs=struct.unpack_from('<HBBIII',raw)
            uv_bytes=b''.join(pack('2f',*point)for point in [(0,0),(1,0),(0,1),(1,1)])
            assert vertices==4 and uv==0
            geometry[0]=(1,pack('HBBIII',flags|4,1,unused,triangles,vertices,morphs)+uv_bytes+raw[16:])
            rows[1]=(15,b''.join(chunk(k,b)for k,b in geometry));body=b''.join(chunk(k,b)for k,b in rows)
        out.append(chunk(kind,body))
    return chunk(16,b''.join(out))
def authored(folder):
    variants=[named_fixture(n)for n in ['Ripped','Fat','Normal']];normal=b''.join(variants)
    files={'normal-stream.dff':normal,'template.dff':variants[2],
           'wrong-order.dff':variants[0]+variants[2]+variants[1],
           'truncated.dff':normal[:-1],'nonzero-tail.dff':normal+b'X',
           'whole-sector-tail.dff':normal+bytes((-len(normal))%2048+2048),'missing-variant.dff':variants[0]+variants[2],
           'sector-padded.dff':normal+bytes((-len(normal))%2048)}
    pixel=bytes([150,100,50,255])*4
    fields=pack('II32s32sIIHHBBBB',9,0x1102,b'cloth',b'',0x500,21,2,2,32,1,4,1)
    files['fixture.txd']=chunk(22,chunk(1,pack('HH',1,2))+chunk(21,chunk(1,fields+pack('I',len(pixel))+pixel)+chunk(3))+chunk(3))
    for name,data in files.items():(folder/name).write_bytes(data)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.parse_args()
    out=ROOT/'local-only/research/cj-assembly-113';out.mkdir(parents=True,exist_ok=True)
    work=Path(tempfile.mkdtemp(prefix='authored-',dir=out));(out/'latest-authored.txt').write_text(str(work)+'\n')
    authored(work)
    paths=[ROOT/'ios/App'/(n+'.swift')for n in NAMES]+[ROOT/'smoke_native_cj_assembly.swift',Path(__file__)]
    before={str(p):sha(p)for p in paths};(work/'source-owner-before.json').write_text(json.dumps(before,indent=2)+'\n')
    command=['xcrun','swiftc','-Onone','-j','1','-parse-as-library','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',*[str(p)for p in paths[:-1]],'-o',str(work/'verify')]
    build=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=240);(work/'compile.log').write_text(build.stdout+build.stderr)
    if build.returncode:print(build.stdout+build.stderr);build.check_returncode()
    run=subprocess.run([str(work/'verify'),str(work)],cwd=ROOT,capture_output=True,text=True,timeout=90);(work/'runtime.log').write_text(run.stdout+run.stderr)
    if run.returncode:print(run.stdout+run.stderr);run.check_returncode()
    assert all(sha(Path(p))==h for p,h in before.items()),'authored test or source changed'
    report=json.loads((work/'report.json').read_text());report.update(sourcesUnchanged=True,sourceSHA256=before)
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items()if k!='sourceSHA256'},indent=2))
if __name__=='__main__':main()
