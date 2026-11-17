#!/usr/bin/env python3
"""Build source-only legacy UDP transport into owner-local Apple C archives."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,platform,shlex,subprocess,sys,time

ROOT=Path(__file__).resolve().parent
SOURCE=ROOT/'native-samp'

def run(command,env,log,cwd=SOURCE):
    began=time.monotonic()
    result=subprocess.run(command,cwd=cwd,env=env,capture_output=True,text=True)
    log.write_text(result.stdout+result.stderr)
    return {'returncode':result.returncode,'seconds':round(time.monotonic()-began,3),'log':str(log.relative_to(ROOT))}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform',action='append',choices=('host','device','simulator'))
    parser.add_argument('--test',action='store_true',help='Run host race tests and the actual C ABI executable')
    parser.add_argument('--check',action='store_true',help='Check current source hashes and existing requested archives without building')
    parser.add_argument('--output',type=Path,default=ROOT/'local-only/native-samp')
    args=parser.parse_args();out=args.output.resolve()
    try:out.relative_to((ROOT/'local-only').resolve())
    except ValueError:parser.error('Archive output must stay inside owner-local local-only/')
    if not args.check:
        # Read-only archive reuse may follow a link. Rebuilding must never
        # replace a previous checkpoint's libraries, wrappers or build cache.
        for name in ('ios-device','ios-simulator','ios-simulator-x86_64','ios-simulator-arm64','macos-x86_64','macos-arm64','go-cache','go-path'):
            folder=out/name
            if folder.is_symlink():parser.error('Refusing to rebuild through linked output '+name+'; use a fresh local directory or private copies')
            if folder.is_dir() and any(p.is_symlink() for p in folder.iterdir()):parser.error('Refusing linked build files in '+name)
    out.mkdir(parents=True,exist_ok=True)
    paths=[p for p in sorted(SOURCE.rglob('*'))if p.is_file()]+[Path(__file__).resolve()]
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
    if args.check:
        try:
            report=json.loads((out/'build-report.json').read_text())
            assert report['status']=='PASS' and report['sourceUnchanged'] and report['sourceHashes']==hashes
            for kind in args.platform or ['host','device','simulator']:
                name={'host':'macos-'+('arm64'if platform.machine()=='arm64'else'x86_64'),'device':'ios-device','simulator':'ios-simulator'}[kind]
                archive=out/name/'libzgtasa_samp.a';relative=str(archive.relative_to(ROOT))
                record=next(r for r in report['results']if r.get('archive')==relative)
                assert record['returncode']==0 and hashlib.sha256(archive.read_bytes()).hexdigest()==record['sha256']
            print('PASS native legacy transport source/archive checks');return 0
        except (OSError,ValueError,KeyError,AssertionError,StopIteration):
            print('Native legacy transport archives are missing or stale.');return 1
    env=dict(os.environ,GOCACHE=str(out/'go-cache'),GOPATH=str(out/'go-path'),GOFLAGS='-mod=readonly',CGO_ENABLED='1',GOTOOLCHAIN='local')
    host_arch='arm64'if platform.machine()=='arm64'else'amd64'
    host_tag='arm64'if host_arch=='arm64'else'x86_64'
    results=[]
    if args.test:
        test_env=dict(env,GOOS='darwin',GOARCH=host_arch)
        result=run(['go','test','-race','-count=1','./...'],test_env,out/'go-tests.log')
        results.append(dict(stage='host-race-tests',**result));print('host race tests',result['returncode'],flush=True)
        if result['returncode']:
            failure={'status':'FAIL','sourceHashes':hashes,'sourceUnchanged':all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==sha for p,sha in hashes.items()),'results':results,'hostTestsRequested':True}
            (out/'build-report.json').write_text(json.dumps(failure,indent=2)+'\n')
            print((out/'go-tests.log').read_text()[-5000:]);return 1
    requested=args.platform or ['host','device','simulator']
    configurations=[]
    for kind in requested:
        for arch in (['amd64','arm64'] if kind=='simulator' else ['arm64' if kind=='device' else host_arch]):
            configurations.append((kind,arch))
    for kind,arch in configurations:
        tag='x86_64' if arch=='amd64' else 'arm64'
        name={'host':'macos-'+host_tag,'device':'ios-device','simulator':'ios-simulator-'+tag}[kind]
        folder=out/name;folder.mkdir(exist_ok=True)
        sdk={'host':'macosx','device':'iphoneos','simulator':'iphonesimulator'}[kind]
        sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
        clang=subprocess.check_output(['xcrun','--sdk',sdk,'--find','clang'],text=True).strip()
        target=('arm64'if arch=='arm64'else'x86_64')+{'host':'-apple-macos13.0','device':'-apple-ios16.0','simulator':'-apple-ios16.0-simulator'}[kind]
        cc=folder/'cc.sh';cc.write_text('#!/bin/sh\nexec '+shlex.quote(clang)+' -isysroot '+shlex.quote(sdkpath)+' -target '+target+' "$@"\n');cc.chmod(0o755)
        archive=folder/'libzgtasa_samp.a'
        build_env=dict(env,GOOS='darwin'if kind=='host'else'ios',GOARCH=arch,CC=str(cc))
        built=run(['go','build','-trimpath','-buildmode=c-archive','-o',str(archive),'.'],build_env,folder/'build.log')
        result=dict(stage='archive',platform=kind,architecture=tag,target=target,**built)
        if built['returncode']==0:
            result['archive']=str(archive.relative_to(ROOT));result['sha256']=hashlib.sha256(archive.read_bytes()).hexdigest();result['bytes']=archive.stat().st_size
            linked=run([clang,'-target',target,'-isysroot',sdkpath,'-I',str(SOURCE/'include'),str(SOURCE/'tests/abi.c'),str(archive),'-framework','CoreFoundation','-framework','Security','-lresolv','-o',str(folder/'abi-probe')],build_env,folder/'link.log')
            result['SDKLink']=linked
            if kind=='host'and args.test and linked['returncode']==0:result['hostABI']=run([str(folder/'abi-probe')],build_env,folder/'abi.log')
        results.append(result);print(kind,tag,'archive',result['returncode'],'SDK link',result.get('SDKLink',{}).get('returncode'),flush=True)
    if 'simulator' in requested:
        slices=[x for x in results if x.get('platform')=='simulator' and x.get('stage')=='archive']
        universal={'stage':'universal-simulator','platform':'simulator','returncode':1}
        folder=out/'ios-simulator';folder.mkdir(exist_ok=True)
        temporary=folder/'libzgtasa_samp.next.a';archive=folder/'libzgtasa_samp.a'
        if len(slices)==2 and all(x['returncode']==0 and x.get('SDKLink',{}).get('returncode')==0 for x in slices):
            merged=run(['xcrun','lipo','-create',*[str(ROOT/x['archive'])for x in slices],'-output',str(temporary)],env,folder/'lipo.log')
            universal.update(merged)
            if merged['returncode']==0:
                architectures=subprocess.check_output(['xcrun','lipo','-archs',str(temporary)],text=True).split()
                universal['architectures']=architectures
                probes=[]
                sdkpath=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
                clang=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--find','clang'],text=True).strip()
                for tag in ('x86_64','arm64'):
                    target=tag+'-apple-ios16.0-simulator'
                    link=run([clang,'-target',target,'-isysroot',sdkpath,'-I',str(SOURCE/'include'),str(SOURCE/'tests/abi.c'),str(temporary),'-framework','CoreFoundation','-framework','Security','-lresolv','-o',str(folder/('abi-probe-'+tag))],env,folder/('link-'+tag+'.log'))
                    probes.append(dict(architecture=tag,**link))
                universal['SDKLinks']=probes
                universal['returncode']=0 if set(architectures)=={'x86_64','arm64'} and all(p['returncode']==0 for p in probes) else 1
                if universal['returncode']==0:
                    temporary.replace(archive)
                    universal.update(archive=str(archive.relative_to(ROOT)),sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),bytes=archive.stat().st_size)
        temporary.unlink(missing_ok=True)
        results.append(universal);print('universal Simulator',universal['returncode'],flush=True)
    unchanged=all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==sha for p,sha in hashes.items())
    passed=unchanged and all(x['returncode']==0 and x.get('SDKLink',{}).get('returncode',0)==0 and x.get('hostABI',{}).get('returncode',0)==0 for x in results)
    report={'status':'PASS'if passed else'FAIL','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceUnchanged':unchanged,'sourceHashes':hashes,'results':results,'hostTestsRequested':args.test,'limits':['Apple SDK compilation and standalone links are not app installation or gameplay acceptance','Raw RakNet transport; native auth, RPC world implementation and game synchronization remain application responsibilities','Upstream source supports inbound split assembly; outbound payloads are bounded8191bytes and not fragmented here']}
    (out/'build-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(report['status'],'source unchanged',unchanged)
    return 0 if passed else 1

if __name__=='__main__':sys.exit(main())
