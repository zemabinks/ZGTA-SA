#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Narrow app-owned LAN access snapshot plus actual gated stock HTTP requests."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/stock-asset-access';OUT.mkdir(parents=True,exist_ok=True)
def execute(label,command,timeout):
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=timeout)
    (OUT/(label+'.stdout.log')).write_text(result.stdout);(OUT/(label+'.stderr.log')).write_text(result.stderr)
    if result.returncode:raise RuntimeError(label+'\n'+result.stdout+result.stderr)
    return result.stdout

binary=OUT/'stock-access-tests'
execute('build',['xcrun','swiftc','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',
                 str(ROOT/'ios/App/NativeStockAssetAccess.swift'),str(ROOT/'tests/stock_asset_access/main.swift'),'-o',str(binary)],90)
boundary=json.loads(execute('boundary',[str(binary)],30))
execute('loader',['python3','test_samp_stock_asset_loader.py'],360)
loader=json.loads((ROOT/'local-only/research/stock-asset-loader/report.json').read_text())
assert loader['checks']>=109 and loader['defaultCookieFree'] and loader['optInStockCookieOnly'] and not loader['redirectFollowed']
execute('server',['python3','test_stock_native_server.py'],120)
server=json.loads((ROOT/'local-only/research/stock-native-server/report.json').read_text())
assert server['checks']>=109 and server['ownedHTTPResources']==12
sdk=execute('sdk',['xcrun','--sdk','iphoneos','--show-sdk-path'],30).strip()
names=['NativeStockAssetAccess.swift','NativeSAMPStockModels.swift','NativeRenderWareDFF.swift','NativeRenderWareTXD.swift',
       'NativeRenderWareModel.swift','NativeRenderWareCollision.swift','NativeSAMPStockAssetLoader.swift']
execute('ios-typecheck',['xcrun','swiftc','-typecheck','-target','arm64-apple-ios15.0','-sdk',sdk,
                        '-module-cache-path','/private/tmp/zgtasa-core-swift-modules',*[str(ROOT/'ios/App'/name) for name in names]],120)
report={'status':'PASS','cookieBoundaryChecks':boundary['checks'],'stockLoaderChecks':loader['checks'],
        'stockLoaderHTTPRequests':loader['httpRequests'],'stockServerChecks':server['checks'],
        'ownedHTTPResources':server['ownedHTTPResources'],'defaultStockAccess':'credential-free',
        'optInStockAccess':'Only exact first-party zgta_access; no auto cookies, credentials or redirects',
        'ios15Arm64Typecheck':'PASS','scope':'App-session snapshot and bounded HTTP access only; renderer integration and physical iPhone play remain separate.',
        'sourceSHA256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in
                        ['ios/App/NativeStockAssetAccess.swift','ios/App/NativeSAMPStockAssetLoader.swift',
                         'tests/stock_asset_access/main.swift','tests/stock_asset_loader/main.swift',
                         'test_samp_stock_asset_loader.py','test_stock_asset_access.py']}}
(OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,indent=2,sort_keys=True))
