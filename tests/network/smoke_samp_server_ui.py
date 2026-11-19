#!/usr/bin/env python3
"""Actual legacy UI models/codecs, C++ Huffman golden and Apple UIKit typechecks."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile,datetime,sys
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/samp-server-ui';out.mkdir(parents=True,exist_ok=True)
 sdkNames=['ios/App/ServerAddress.swift','ios/App/NativeWorldEnvironment.swift','ios/App/NativeGameHUD.swift']
 names=['ios/App/NativeSAMPProtocol.swift','ios/App/NativeSAMPTextCodec.swift','ios/App/NativeSAMPServerUI.swift','ios/App/NativeSAMPTextDrawOverlay.swift','tests/network/smoke_samp_server_ui.swift','tests/network/smoke_samp_server_ui.py']
 before={name:(ROOT/name).read_bytes()for name in names+sdkNames};results=[]
 with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as directory:
  work=Path(directory);sources=[]
  for name in names[:4]:
   p=work/Path(name).name;p.write_bytes(before[name]);sources.append(str(p))
  sdkSources=[]
  for name in sdkNames:
   p=work/Path(name).name;p.write_bytes(before[name]);sdkSources.append(str(p))
  (work/'main.swift').write_bytes(before['tests/network/smoke_samp_server_ui.swift'])
  command=['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),*sources,str(work/'main.swift'),'-o',str(work/'verify')]
  r=subprocess.run(command,capture_output=True,text=True);(out/'compile.log').write_text(r.stdout+r.stderr);results.append({'stage':'host-compile','returncode':r.returncode})
  if r.returncode:print(r.stdout+r.stderr);r.check_returncode()
  r=subprocess.run([str(work/'verify')],capture_output=True,text=True);(out/'runtime.log').write_text(r.stdout+r.stderr);results.append({'stage':'host-golden-runtime','returncode':r.returncode});print(r.stdout+r.stderr,end='');r.check_returncode()
  for sdk,target in [('iphoneos','arm64-apple-ios16.0'),('iphonesimulator','x86_64-apple-ios16.0-simulator')]:
   path=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
   r=subprocess.run(['xcrun','swiftc','-typecheck','-sdk',path,'-target',target,'-module-cache-path',str(out/('modules-'+sdk)),*sources,*sdkSources],capture_output=True,text=True)
   (out/(sdk+'.log')).write_text(r.stdout+r.stderr);results.append({'stage':sdk+'-UIKit-typecheck','returncode':r.returncode});print(sdk,r.returncode)
 unchanged=all((ROOT/n).read_bytes()==b for n,b in before.items())
 report={'status':'PASS'if unchanged and all(x['returncode']==0 for x in results)else'FAIL','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceUnchanged':unchanged,'sourceHashes':{n:hashlib.sha256(b).hexdigest()for n,b in before.items()},'results':results,'limits':['Protocol/codec/controller compilation; no rendered dialog or actual-server account acceptance','Original typography, all TextDraw layout/preview paths and physical input remain separate acceptance']}
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(report['status']);return 0 if report['status']=='PASS'else 1
if __name__=='__main__':sys.exit(main())
