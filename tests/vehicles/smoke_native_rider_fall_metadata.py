#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual rider metadata decoder and optional clip lookup on authored JSON."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--prepare-only',action='store_true');a=p.parse_args()
 os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/rider-fall-metadata-168'/str(time.time_ns());out.mkdir(parents=True)
 source=ROOT/'ios/App/NativeRiderAnimation.swift';test=Path(__file__).with_suffix('.swift');paths=[source,test,Path(__file__).resolve()]
 frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
 text=source.read_text();metadata=text[:text.index('/// Seated public bA.es/ec')]
 # Unused configuration return type is an explicit carrier, not an animation
 # implementation. The complete production definitions and lookup bodies stay.
 carrier=out/'Metadata.swift';carrier.write_text('import simd\n'+metadata+'\nenum NativeRiderAnimation {struct Configuration {var astride:Bool;var clips:[String:String];var passenger:Bool;var side:Int}}\n')
 report=dict(status='PREPARED',sourceHashes=frozen,compilerInvoked=False,scope=__doc__)
 try:
  if not a.prepare_only:
   report['compilerInvoked']=True
   command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-j','1','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(carrier),str(test),'-o',str(out/'gate')]
   r=subprocess.run(command,capture_output=True,text=True,timeout=180);(out/'compile.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
   r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=60);report.update(exitCode=r.returncode,output=r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
 except BaseException as e:report.update(status='FAIL',error=repr(e));raise
 finally:
  report['sourcesHeld']=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items());(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print({k:v for k,v in report.items()if k!='sourceHashes'})
if __name__=='__main__':main()
