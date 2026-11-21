#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual trace/query role dispatch with compact traffic contact replicas."""
from pathlib import Path
import argparse,hashlib,json,os,platform,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def block(source,needle):
    start=source.index(needle);at=source.index('{',start);depth=1;end=at+1
    while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--historical-renderer',type=Path);args=p.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/camera-roles-165'/str(time.time_ns());out.mkdir(parents=True)
    names=['ServerAddress','SwiftRapierWorld','NativeWorldRay','NativeGameInput','NativeGameCamera','NativePassiveCameraTrace','NativeAmbientTrafficBodies']
    files=[ROOT/'ios/App'/(n+'.swift')for n in names]
    renderer=ROOT/'ios/App/NativeWorldRenderer.swift';test=Path(__file__).with_suffix('.swift')
    library=ROOT/'local-only/native-physics'/('macos-'+platform.machine())/'libzgtasa_native_physics.a'
    inputs=[*files,renderer,test,Path(__file__).resolve(),library]+([args.historical_renderer.resolve()]if args.historical_renderer else[])
    frozen={str(f):hashlib.sha256(f.read_bytes()).hexdigest()for f in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,results=[],scope=__doc__)
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        variants=([('historical',args.historical_renderer.resolve())]if args.historical_renderer else[])+[('candidate',renderer)]
        for label,path in variants:
            source=path.read_text();methods='\n'.join(block(source,n)for n in ['    private func cameraRay(','    private func worldRay('])
            trace=block(source,'        gameCamera.trace =')
            harness=test.read_text().replace('// ACTUAL_QUERY_METHODS',methods).replace('// ACTUAL_TRACE_ASSIGNMENT',trace)
            code=out/(label+'.swift');code.write_text(harness);exe=out/label
            command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*map(str,files),str(code),'-L',str(library.parent),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(exe)]
            with(out/(label+'-compile.log')).open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
            assert r.returncode==0,(out/(label+'-compile.log')).read_text()[-6000:]
            r=subprocess.run([str(exe),str(out/(label+'-trace'))],capture_output=True,text=True,timeout=60)
            (out/(label+'-runtime.log')).write_text(r.stdout+r.stderr);row=dict(label=label,compileExit=0,exitCode=r.returncode,output=r.stdout+r.stderr);report['results'].append(row);save()
            if label=='historical':assert r.returncode!=0 and 'Passenger used driver collision mask'in row['output'],row
            else:assert r.returncode==0,row
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in frozen.items());save();print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
