#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compile the actual Swift encoder; reassemble its authored bytes in Python."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tools.development.read_native_diagnostics import reassemble,PREFIX

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--encoder',type=Path,default=ROOT/'ios/App/NativeDiagnosticChunks.swift')
 args=parser.parse_args()
 assert os.getpriority(os.PRIO_PROCESS,0)==15
 out=ROOT/'local-only/research/diagnostic-chunks-178'/str(time.time_ns());out.mkdir(parents=True)
 paths=[ROOT/n for n in ['ios/App/NativeDiagnosticChunks.swift','tests/ui/smoke_native_diagnostic_chunks.swift','tools/development/read_native_diagnostics.py','tests/ui/test_native_diagnostic_reader.py',__file__]]
 paths[0]=args.encoder.resolve()
 frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
 program=out/'main.swift';program.write_text(paths[1].read_text())
 report={'status':'RUNNING','sources':frozen,'scope':'Actual Swift encoder / Python decoder, authored bytes only; not OSLog runtime or gameplay acceptance'}
 def run(name,args):
  start=time.time()
  with(out/(name+'.log')).open('x')as log:r=subprocess.run(args,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=180)
  report[name]={'exitCode':r.returncode,'seconds':time.time()-start};assert r.returncode==0,name
 try:
  run('reader-unit',[sys.executable,'-m','unittest','tests.ui.test_native_diagnostic_reader'])
  run('compiler',['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(paths[0]),str(program),'-o',str(out/'encode')])
  run('encoder',[str(out/'encode'),str(out)])
  rows=json.loads((out/'authored-records.json').read_text());lines=[PREFIX+line for row in rows for line in row['lines']]
  records=reassemble(lines[::-1]+lines[:1])
  assert len(records)==len(rows)==9
  for row in rows:assert records[row['id']]==(out/row['file']).read_bytes()
  report.update(status='PASS',authoredRecords=len(rows),exactRoundTripBytes=sum(map(len,records.values())),lineCount=len(lines),sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items()))
  assert report['sourcesHeld']
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'path':str(out),**report}))
if __name__=='__main__':main()
