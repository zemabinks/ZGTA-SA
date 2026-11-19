#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Literal renderer clock/fallback calls and actual rider/bike time consumers."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from tests.vehicles.smoke_native_vehicle_transparency import block

def carrier(renderer):
    draw=block(renderer,'    private func drawActors(')
    a=draw.index('        let riderTime = ');b=draw.index('        let riderIDs = ',a)
    start=draw.index('ownRiderAnimation?.update(');at=start+draw[start:].index('(');depth=0
    for end in range(at,len(draw)):
        if draw[end]=='(':depth+=1
        elif draw[end]==')':
            depth-=1
            if depth==0:break
    else:raise AssertionError('Unclosed actual rider call')
    return draw[a:b],draw[start:end+1]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--negative-renderer',type=Path);args=parser.parse_args()
    out=ROOT/'local-only/research/rider-hitches-148'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeRiderAnimation.swift','NativeBoardingAnimation.swift','NativeRiderPlayback.swift','NativeRemoteBikeAnimation.swift']
    files=[ROOT/'ios/App'/n for n in names]+[ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'ios/App/NativeSkeletalActor.swift',Path(__file__),Path(__file__).with_suffix('.swift')]
    if args.negative_renderer:files.append(args.negative_renderer.resolve())
    before={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
    library=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text().split('struct NativeSkeletalLayer {',1)[0].replace('import Metal\n','')
    assert 'final class NativeSkeletalAnimationLibrary'in library and 'MTL'not in library
    (out/'ActualLibrary.swift').write_text(library)
    results=[]
    for label,renderer in ([('historical-negative',args.negative_renderer.resolve())]if args.negative_renderer else[])+[('current',ROOT/'ios/App/NativeWorldRenderer.swift')]:
        clock,call=carrier(renderer.read_text());source=Path(__file__).with_suffix('.swift').read_text().replace('// ACTUAL_CLOCK\n',clock).replace('/* ACTUAL_FALLBACK */',call)
        work=out/label;work.mkdir();(work/'Carrier.swift').write_text(source)
        command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*[str(ROOT/'ios/App'/n)for n in names],str(out/'ActualLibrary.swift'),str(work/'Carrier.swift'),'-o',str(work/'probe')]
        started=time.monotonic()
        with(work/'compile.log').open('w')as log:built=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
        if built.returncode:print((work/'compile.log').read_text()[-7000:]);built.check_returncode()
        with(work/'runtime.log').open('w')as log:ran=subprocess.run([str(work/'probe')],stdout=log,stderr=subprocess.STDOUT,timeout=30)
        value=json.loads((work/'runtime.log').read_text());expected=label=='historical-negative'
        if expected:assert ran.returncode==1 and value['status']=='FAIL' and value['failure'].startswith('valid rider interval retained'),value
        else:assert ran.returncode==0 and value['status']=='PASS',value
        results.append(dict(label=label,compileExit=0,runExit=ran.returncode,expectedNegative=expected,result=value,seconds=time.monotonic()-started,generatedSHA256=hashlib.sha256(source.encode()).hexdigest()))
    assert all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in before.items())
    report=dict(status='PASS',results=results,sourceUnchanged=True,sourceHashes=before,actualNice=os.getpriority(os.PRIO_PROCESS,0),scope='Literal renderer prelude and local fallback expression; actual pose clock, seated animator and remote-bike consumer, authored UI/time/packet/clip-duration boundaries. No rendered, network, physical-device or retail acceptance.',work=str(out))
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
