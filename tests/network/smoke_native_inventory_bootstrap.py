#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual baseline-vs-pending inventory timer ownership at the controller boundary."""
from pathlib import Path
import hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
 os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/inventory-bootstrap-172'/str(time.time_ns());out.mkdir(parents=True)
 names=['ServerAddress','NativeConnectionRecovery','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState']
 files=[ROOT/'ios/App'/(n+'.swift')for n in names]+[ROOT/'ios/App/NativeGameViewController.swift',Path(__file__).resolve(),Path(__file__).with_suffix('.swift')]
 frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 source=files[-3].read_text();start=source.index('        weapons.onNeedsResync =');brace=source.index('{',start);end=brace+1;depth=1
 while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
 callback=source[start:end]
 (out/'Gate.swift').write_text(files[-1].read_text().replace('// ACTUAL_INVENTORY_RESYNC_CALLBACK',callback))
 report=dict(status='RUNNING',sourceHashes=frozen,scope='Actual GameVC callback, NativeWeaponState/Prediction and NativeConnectionRecovery; injected clocks and explicit socket owner boundary. No URLSession, Renderer or App claim')
 def save():
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
 save()
 try:
  with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-num-threads','1','-whole-module-optimization','-Onone','-module-cache-path',str(out/'modules'),*map(str,files[:len(names)]),str(out/'Gate.swift'),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=240)
  report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-4000:]
  r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=60);report.update(exitCode=r.returncode,output=r.stdout+r.stderr);save();assert r.returncode==0,r.stdout+r.stderr
  report['status']='PASS'
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:report.update(sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items()),completedAt=time.time());save();print({k:v for k,v in report.items()if k!='sourceHashes'})
if __name__=='__main__':main()
