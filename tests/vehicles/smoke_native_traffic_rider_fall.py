#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Native astride clip/anchor owner, with optional owner-local scalar reference."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--prepare-only',action='store_true');p.add_argument('--reference',type=Path);a=p.parse_args()
 os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/traffic-rider-fall-168'/str(time.time_ns());out.mkdir(parents=True)
 files=[ROOT/'ios/App/NativeTrafficRiderFall.swift',Path(__file__).with_suffix('.swift'),Path(__file__).resolve()]
 if a.reference:
  a.reference=a.reference.resolve();d=json.loads(a.reference.read_text());assert d['schemaVersion']==1 and d['caseCount']==15 and d['stepCount']==68
  assert a.reference.stat().st_size<1048576
  for value in d['parents'].values():
   if isinstance(value,dict)and 'path'in value and 'sha256'in value:assert hashlib.sha256(Path(value['path']).read_bytes()).hexdigest()==value['sha256']
  files.append(a.reference)
 frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 report=dict(status='PREPARED',sourceHashes=frozen,compilerInvoked=False,scope='Actual native clip/anchor/frozen-matrix policy with authored clips and optional archived scalar observations; no bone sampling/interpolation, GPU, detached lifetime, NPC handoff, physical/network or retail acceptance. Compares final selected sample, not repeated source sampler-call counts.')
 try:
  if not a.prepare_only:
   report['compilerInvoked']=True
   command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-j','1','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(files[0]),str(files[1]),'-o',str(out/'gate')]
   r=subprocess.run(command,capture_output=True,text=True,timeout=180);(out/'compile.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
   r=subprocess.run([str(out/'gate')]+([str(a.reference)]if a.reference else[]),capture_output=True,text=True,timeout=60);report.update(exitCode=r.returncode,output=r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
 except BaseException as e:report.update(status='FAIL',error=repr(e));raise
 finally:
  report['sourcesHeld']=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items());(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print({k:v for k,v in report.items()if k!='sourceHashes'})
if __name__=='__main__':main()
