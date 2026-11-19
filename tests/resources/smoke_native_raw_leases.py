#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual raw-store/lease regression with authored extractor/folder bytes only."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,os,signal,subprocess,time
from tests.resources.native_raw_test_support import pinned_host_archive
ROOT=Path(__file__).resolve().parents[2]
NAMES=['NativeResourceManifest','NativeResourceStore','NativeRawResourceLease','NativeRawResourceStore']
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def run(command,log,timeout=180):
    p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True)
    try:output,_=p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGTERM)
        try:output,_=p.communicate(timeout=3)
        except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);output,_=p.communicate()
        log.write_text(output);raise RuntimeError('Bounded raw lease subprocess timeout')
    log.write_text(output);return p.returncode,output

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--installer-archive',type=Path);parser.add_argument('--sdk-check',action='store_true');args=parser.parse_args()
    out=ROOT/'local-only/research/raw-leases-109'/('run-'+str(time.time_ns()));source=out/'source';source.mkdir(parents=True)
    archive=pinned_host_archive(args.installer_archive)
    paths=[ROOT/'ios/App'/(n+'.swift')for n in NAMES]+[ROOT/'native-installer/swift/NativeISOExtraction.swift',ROOT/'native-installer/swift/NativeRawResourceSelection.swift',ROOT/'tests/resources/smoke_native_raw_leases.swift',Path(__file__),ROOT/'tests/resources/native_raw_test_support.py']
    before={str(p.relative_to(ROOT)):digest(p)for p in paths};sources=[]
    for p in paths:
        if p.suffix=='.swift':target=source/p.name;target.write_bytes(p.read_bytes());sources.append(target)
    command=['xcrun','swiftc','-swift-version','5','-parse-as-library','-I',str(ROOT/'native-installer/include'),'-module-cache-path','/private/tmp/zgtasa-core-swift-modules',*map(str,sources),str(archive),'-lz','-o',str(out/'leases')]
    code,output=run(command,out/'compile.log',300)
    if code:print(output[-6000:]);raise SystemExit(code)
    code,output=run([str(out/'leases'),str(out/'fixture')],out/'runtime.log',180)
    sdk=[]
    if code==0 and args.sdk_check:
        for name,target in [('iphoneos','arm64-apple-ios16.0'),('iphonesimulator','arm64-apple-ios16.0-simulator'),('iphonesimulator','x86_64-apple-ios16.0-simulator')]:
            sdkpath=subprocess.check_output(['xcrun','--sdk',name,'--show-sdk-path'],text=True).strip()
            command=['xcrun','--sdk',name,'swiftc','-swift-version','5','-sdk',sdkpath,'-target',target,'-typecheck','-I',str(ROOT/'native-installer/include'),'-module-cache-path',str(out/'sdk-modules'),*map(str,sources[:-1])]
            status,text=run(command,out/('sdk-'+target+'.log'),240);sdk.append({'target':target,'status':status})
            if status:print(text[-4000:]);code=status;break
    unchanged=all(digest(ROOT/name)==value for name,value in before.items())
    report={'status':'PASS'if code==0 and unchanged else'FAILED_OR_SOURCE_CHANGED','exitCode':code,'sourceUnchanged':unchanged,'sourceHashes':before,'installerArchiveSHA256':digest(archive),'installerArchivePinnedToCurrentCHashes':True,'sdkTypechecks':sdk,'output':str(out),'limits':['Authored source/extractor/raw file fixtures; no original assets or actual App data.','No services, networking, hardware, UI, playback, PCM export or gameplay activation.','Pinned C bridge is linked read-only; no C source/project/playback changes.']}
    if(out/'fixture/report.json').is_file():report['runtime']=json.loads((out/'fixture/report.json').read_text())
    (out/'acceptance.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));print(output[-4000:])
    if report['status']!='PASS':raise SystemExit(1)
if __name__=='__main__':main()
