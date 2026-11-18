#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Asset-free fixed-profile producer/parser tests. No owner activation mode."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from smoke_native_cj_assembly import authored,NAMES
from prepare_native_cj_profile import prepare,candidates,FILES,NAME

ROOT=Path(__file__).resolve().parent

def fixture(work):
    cases=work/'cases';cases.mkdir();authored(cases)
    pieces=work/'pieces';pieces.mkdir();local=work/'private';local.mkdir()
    texture_names={'player_torso.txd':'torso','vest.txd':'vest','player_face.txd':'face',
                   'jeansdenim.txd':'legs','sneakerbincblk.txd':'sneakerbincblk'}
    for role,name in FILES.items():
        if role=='rules':continue
        if name.endswith('.txd'):
            data=(cases/'fixture.txd').read_bytes();old=b'cloth'+bytes(27)
            assert data.count(old)==1
            value=texture_names[name].encode();data=data.replace(old,value+bytes(32-len(value)),1)
        else:data=(cases/('template.dff' if role=='template' else 'normal-stream.dff')).read_bytes()
        (pieces/name).write_bytes(data)
    rules=work/'rules.dat';rules.write_text('rule\nCUTS head cs_head\nCUTS hands cs_hands\nend\n')
    receipt=prepare(local,pieces,rules)
    return local,Path(receipt['output'])

def main():
    base=ROOT/'local-only/research/cj-runtime-113';base.mkdir(parents=True,exist_ok=True)
    work=Path(tempfile.mkdtemp(prefix='authored-',dir=base));(base/'latest-authored.txt').write_text(str(work)+'\n')
    local,body=fixture(work)
    assert len(candidates(local))==13
    try:prepare(local,work/'pieces',work/'rules.dat')
    except ValueError:pass
    else:raise AssertionError('existing overlay must be preserved')
    paths=[ROOT/'ios/App'/(n+'.swift')for n in NAMES+['NativeCJProfile']]+[ROOT/'smoke_native_cj_profile.swift']
    watched=paths+[Path(__file__),ROOT/'prepare_native_cj_profile.py',ROOT/'smoke_native_cj_assembly.py']
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in watched}
    run=subprocess.run(['xcrun','swiftc','-Onone','-j','1','-parse-as-library','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',*map(str,paths),'-o',str(work/'verify')],capture_output=True,text=True,timeout=240)
    (work/'compile.log').write_text(run.stdout+run.stderr);run.check_returncode()
    run=subprocess.run([str(work/'verify'),str(body),str(work/'report.json')],capture_output=True,text=True,timeout=90)
    (work/'runtime.log').write_text(run.stdout+run.stderr);run.check_returncode()
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    report=json.loads((work/'report.json').read_text());assert report['status']=='PASS'
    report.update(sourcesUnchanged=True,sourceSHA256=hashes,producerChecks=2)
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items()if k!='sourceSHA256'},indent=2))
if __name__=='__main__':main()
