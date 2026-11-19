#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Portable actual remote-bike class/Renderer-owner gate; no game resources."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile,time

ROOT=Path(__file__).resolve().parent
BRIDGE='''// TEST-ONLY HISTORICAL INTERFACE BRIDGE. The old algorithm below is
// unchanged; this overload deliberately ignores the new owner argument.
extension NativeRemoteBikeAnimation {
    struct Owner:Equatable {
        var appearance:String
        var vehicleID:String?
        var asset:ObjectIdentifier?
    }
    func update(model:String,maxLean:Double?,now:Double,delta:Double,
                sample:Sample,previous:Sample?,owner:Owner?=nil)->Frame {
        update(model:model,maxLean:maxLean,now:now,delta:delta,sample:sample,previous:previous)
    }
}
'''

def sha(data):return hashlib.sha256(data).hexdigest()
def renderer_dispatch(source):
    marker='let frame=bike.update(model:model,'
    assert source.count(marker)==1,'Actual Renderer bike dispatch must be unique'
    call=source.index(marker)
    cache='let bike=remoteBikeAnimations[player.id] ?? NativeRemoteBikeAnimation();remoteBikeAnimations[player.id]=bike'
    begin=source.rfind(cache,0,call)
    assert begin>=0 and source[begin+len(cache):call].strip()=='','Cache/dispatch relationship changed'
    start=source.index('(',call);depth=1;end=start+1
    while depth:
        assert end<len(source),'Unterminated actual call'
        depth+=(source[end]=='(')-(source[end]==')');end+=1
    block=source[begin:end]
    owner='owner:.init(appearance:player.code,vehicleID:player.vehicleID,asset:actorMeshes[name].map{ObjectIdentifier($0.vertices)})'
    assert owner in ''.join(block.split()),'Actual owner fields/identity changed'
    return block

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only',action='store_true',help='Write source carriers/commands, do not invoke a compiler or executable')
    parser.add_argument('--negative-root',type=Path,help='Optional genuine pre-owner checkout; no historical source is embedded')
    args=parser.parse_args()
    paths=[ROOT/'ios/App/NativeRemoteBikeAnimation.swift',ROOT/'ios/App/NativeWorldRenderer.swift',Path(__file__).resolve(),ROOT/'smoke_native_remote_bike_owner.swift']
    source,renderer,_,test=[p.read_text() for p in paths]
    before={str(p):sha(p.read_bytes()) for p in paths}
    dispatch=renderer_dispatch(renderer)
    assert test.count('// ACTUAL_RENDERER_DISPATCH')==1
    carrier=test.replace('// ACTUAL_RENDERER_DISPATCH',dispatch)
    out=ROOT/'local-only/research/remote-bike-owner-122';out.mkdir(parents=True,exist_ok=True)
    work=Path(tempfile.mkdtemp(prefix='gate-',dir=out));stages=[]
    def stage(label,algorithm,bridge=''):
        folder=work/label;folder.mkdir()
        actual=folder/'NativeRemoteBikeAnimation.swift';actual.write_text(algorithm)
        main=folder/'main.swift';main.write_text(carrier)
        files=[str(actual)]
        if bridge:
            b=folder/'HistoricalInterfaceBridge.swift';b.write_text(bridge);files.append(str(b))
        binary=folder/'verify'
        command=['nice','-n','15',shutil.which('swiftc') or 'swiftc','-O','-whole-module-optimization','-num-threads','1','-swift-version','5','-module-cache-path',str(folder/'modules'),*files,str(main),'-o',str(binary)]
        stages.append({'label':label,'sourceSHA256':sha(algorithm.encode()),'testOnlyBridgeSHA256':sha(bridge.encode()) if bridge else None,
                       'carrierSHA256':sha(carrier.encode()),'compileCommand':command,'binary':str(binary)})
    stage('current',source)
    if args.negative_root:
        old=args.negative_root.resolve()/'ios/App/NativeRemoteBikeAnimation.swift'
        original=old.read_text()
        assert 'struct Owner' not in original and 'owner:Owner?' not in original,'Negative input already implements owner identity'
        paths.append(old);before[str(old)]=sha(old.read_bytes());stage('historical',original,BRIDGE)
    report={'status':'PREPARED_ONLY_NOT_COMPILED','stages':stages,'sourceHashes':before,
            'literalRendererDispatch':dispatch,'literalRendererDispatchSHA256':sha(dispatch.encode()),
            'scope':'Actual Foundation-only bike class and literal Renderer cache/owner argument; authored NSObject buffer identities and samples. No UIKit/Metal/GPU/assets/tables/game services.',
            'historicalControl':'Optional original pre-owner algorithm is copied unchanged; only a labelled test interface type+overload ignores owner and delegates its exact old method.',
            'noOriginalAssetsOrAuditMetadata':True,'preparedOnly':args.prepare_only}
    manifest=work/'report.json';latest=out/'latest.json'
    def save():
        manifest.write_text(json.dumps(report,indent=2)+'\n');latest.write_bytes(manifest.read_bytes())
    save()
    if args.prepare_only:
        assert before=={str(p):sha(p.read_bytes()) for p in paths}
        print(json.dumps({'status':report['status'],'manifest':str(manifest),'stages':len(stages),'compilerInvoked':False},indent=2));return
    results=[]
    for s in stages:
        folder=Path(s['binary']).parent;began=time.monotonic()
        built=subprocess.run(s['compileCommand'],capture_output=True,text=True,timeout=180)
        (folder/'compile.log').write_text(built.stdout+built.stderr)
        if built.returncode:
            report.update(status='FAIL_COMPILE',results=results);save();raise RuntimeError(s['label']+' compile failed; see '+str(folder/'compile.log'))
        modes=['compatibility','owner'] if s['label']=='historical' else ['owner']
        for mode in modes:
            ran=subprocess.run([s['binary'],mode],capture_output=True,text=True,timeout=30)
            output=ran.stdout+ran.stderr;(folder/(mode+'-runtime.log')).write_text(output)
            negative=s['label']=='historical' and mode=='owner'
            ok=(ran.returncode==2 and 'OWNER_CHANGE_SNAP' in output) if negative else (ran.returncode==0 and 'PASS ' in output)
            results.append({'label':s['label'],'mode':mode,'expectedOwnerNegative':negative,'exitCode':ran.returncode,'output':output,'expectationMet':ok})
            if not ok:
                report.update(status='FAIL_RUNTIME',results=results);save();raise RuntimeError('Actual source control failed: '+str(results[-1]))
        s['seconds']=time.monotonic()-began
    unchanged=before=={str(p):sha(p.read_bytes()) for p in paths}
    report.update(status='PASS' if unchanged else 'FAIL_SOURCE_CHANGED',sourceUnchanged=unchanged,results=results)
    save();assert unchanged
    print(json.dumps({'status':report['status'],'results':results,'manifest':str(manifest)},indent=2))

if __name__=='__main__':main()
