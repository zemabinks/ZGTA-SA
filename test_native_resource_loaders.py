#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Portable offline loader/installed-resource regressions; authored fixtures only.

Uses actual immutable Swift loaders, Store/Session and stock metadata sink.
No HTTP listener, original game fixtures, App data, UI or hardware is used.
"""
from pathlib import Path
import hashlib,json,shutil,subprocess,time
ROOT=Path(__file__).resolve().parent
SOURCES=['ServerAddress.swift','NativeStockAssetAccess.swift','NativeResourceManifest.swift','NativeResourceStore.swift','NativeResourceSession.swift','NativeGameCamera.swift','NativeWorldEnvironment.swift','NativeAtmosphere.swift','NativeWaterWaves.swift','NativeRegionalWeather.swift']
def sha(data):return hashlib.sha256(data).hexdigest()
def metadata():
    source=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    marker='private final class LegacyStockMetadataTransfer:NSObject,URLSessionDataDelegate {'
    # This authored helper is the final declaration. Never extract/execute an
    # archived browser or original game script; no such path is read here.
    text=source[source.index(marker):]
    assert text.rstrip().endswith('}') and text.count('private final class LegacyStockMetadataTransfer')==1
    return text

def main():
    out=ROOT/'local-only/research/resource-bypass-109'/('run-'+str(time.time_ns()))
    snapshot=out/'source';snapshot.mkdir(parents=True)
    before={name:(ROOT/'ios/App'/name).read_bytes()for name in SOURCES}
    sink=metadata();harness=(ROOT/'test_native_resource_loaders.swift').read_bytes()
    for name,data in before.items():(snapshot/name).write_bytes(data)
    combined=snapshot/'LoaderRegression.swift';combined.write_text(harness.decode()+'\n'+sink)
    args=['xcrun','swiftc','-swift-version','5','-parse-as-library','-whole-module-optimization','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules']
    args += [str(snapshot/name)for name in SOURCES]+[str(combined),'-o',str(out/'loader-tests')]
    with(out/'compile.log').open('w')as log:compile_run=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,timeout=300)
    if compile_run.returncode:
        print((out/'compile.log').read_text()[-5000:]);raise SystemExit(compile_run.returncode)
    fixture=out/'fixture'
    with(out/'run.log').open('w')as log:run=subprocess.run([str(out/'loader-tests'),str(fixture)],stdout=log,stderr=subprocess.STDOUT,timeout=90)
    unchanged=before=={name:(ROOT/'ios/App'/name).read_bytes()for name in SOURCES}and sink==metadata()and harness==(ROOT/'test_native_resource_loaders.swift').read_bytes()
    report={'status':'PASS'if run.returncode==0 and unchanged else'FAILED_OR_SOURCE_CHANGED','exitCode':run.returncode,'sourceUnchanged':unchanged,'sourceSHA256':{name:sha(data)for name,data in before.items()},'metadataTransferSHA256':sha(sink.encode()),'testSHA256':sha(harness),'command':args,'output':str(out),'limits':['Synthetic folder-only Store receipt and explicitly synthetic runtime validator.','Network path is an injected URLProtocol; no HTTP listener, external request, device, UI or actual App data.','No original assets/scripts/fixtures read or published.','No rendered109 resource-denial or full-game acceptance.']}
    if(fixture/'report.json').is_file():report['checks']=json.loads((fixture/'report.json').read_text())
    (out/'acceptance.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if report['status']!='PASS':print((out/'run.log').read_text()[-4000:]);raise SystemExit(1)
if __name__=='__main__':main()
