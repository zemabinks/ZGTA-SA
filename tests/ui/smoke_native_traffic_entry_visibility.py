#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Literal native HUD/tap candidate source, with an optional older carrier."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[2]
def block(source,marker):
 start=source.index(marker);brace=source.index('{',start);end=brace+1;depth=1
 while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end].replace('private ','')
def main():
 p=argparse.ArgumentParser();p.add_argument('--source',type=Path);p.add_argument('--prepare-only',action='store_true');a=p.parse_args()
 os.setpriority(os.PRIO_PROCESS,0,15);source=a.source or ROOT/'ios/App/NativeGameViewController.swift';text=source.read_text()
 start=text.index('vehicleButton.isHidden = !climbing');end=text.index('\n            }',start);visibility=text[start:end]
 marker='private var nearbyTrafficVehicleForEntry:'
 candidate=block(text,marker)if marker in text else 'var nearbyTrafficVehicleForEntry:NativeAmbientTrafficScene.Frame?{nil}'
 if marker in text:
  action=block(text,'@objc private func toggleVehicle()');assert 'nearbyTrafficVehicleForEntry'in action,'Visibility and actual tap must share candidate admission'
 carrier=(ROOT/'tests/ui/smoke_native_traffic_entry_visibility.swift').read_text().replace('// ACTUAL_TRAFFIC_CANDIDATE',candidate).replace('// ACTUAL_VISIBILITY',visibility)
 out=ROOT/'local-only/research/traffic-entry-182';out.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='visibility-',dir=out));swift=work/'verify.swift';swift.write_text(carrier)
 executable=work/'verify';command=['xcrun','swiftc','-parse-as-library','-j','1','-O','-whole-module-optimization','-num-threads','1','-swift-version','5','-module-cache-path',str(work/'modules'),str(swift),'-o',str(executable)]
 report=dict(status='PREPARED_NOT_RUN',at=time.time(),source=str(source),sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),carrierSHA256=hashlib.sha256(carrier.encode()).hexdigest(),visibility=visibility,candidate=candidate,command=command,scope='Literal controller predicates with authored renderer/network/button boundaries. No UIKit, actual normal entry, server consent, hardware or retail acceptance.')
 receipt=work/'report.json';receipt.write_text(json.dumps(report,indent=2)+'\n');print(str(receipt),flush=True)
 if a.prepare_only:return
 compiled=subprocess.run(command,capture_output=True,text=True,timeout=180);(work/'compile.log').write_text(compiled.stdout+compiled.stderr);report['compilerExit']=compiled.returncode
 if compiled.returncode:report['status']='COMPILE_FAILURE';receipt.write_text(json.dumps(report,indent=2)+'\n');raise SystemExit(compiled.returncode)
 run=subprocess.run([str(executable)],capture_output=True,text=True,timeout=30);(work/'run.log').write_text(run.stdout+run.stderr);report.update(status='PASS_LITERAL_SOURCE'if run.returncode==0 else'RUNTIME_FAILURE',exitCode=run.returncode,output=run.stdout+run.stderr,sourcesHeld=hashlib.sha256(source.read_bytes()).hexdigest()==report['sourceSHA256']);receipt.write_text(json.dumps(report,indent=2)+'\n');print(run.stdout+run.stderr,end='');raise SystemExit(run.returncode)
if __name__=='__main__':main()
