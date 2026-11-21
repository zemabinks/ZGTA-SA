#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual HUD viewport/draw branches with authored geometry recording spies.

Portable geometry coverage only. UIKit clipping/pixels require the actual App.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def body(source,marker):
 start=source.index('{',source.index(marker));depth=1;end=start+1
 while depth:
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  end+=1
 return source[start+1:end-1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,default=ROOT/'ios/App/NativeGameHUD.swift');p.add_argument('--draw-only',action='store_true');p.add_argument('--prepare-only',action='store_true');args=p.parse_args()
 source=args.source.read_text();layout=body(source[source.index('final class NativeGameHUD: UIView'):],'override func layoutSubviews()')
 marker='// The HUD leaves space'if'// The HUD leaves space'in layout else'// The parent HUD excludes'
 layout=layout[layout.index(marker):];draw=body(source[source.index('private final class NativeAimHUDView'):],'override func draw(_ rect: CGRect)')
 scaffold=(ROOT/'tests/ui/smoke_native_scope_layout.swift').read_text();scaffold=scaffold.replace('/* ACTUAL_VIEWPORT_LAYOUT */',layout).replace('/* ACTUAL_SIGHT_DRAW */',draw).replace('/* DRAW_ONLY */','true'if args.draw_only else'false')
 out=ROOT/'local-only/research/scope-layout-178'/str(time.time_ns());out.mkdir(parents=True);program=out/'main.swift';program.write_text(scaffold)
 frozen={str(path.resolve()):hashlib.sha256(path.read_bytes()).hexdigest()for path in [args.source,Path(__file__),ROOT/'tests/ui/smoke_native_scope_layout.swift']}
 report={'status':'PREPARED_NOT_COMPILED','source':str(args.source.resolve()),'sourceSHA256':frozen,'drawOnly':args.draw_only,'scope':'Actual source branches plus geometry spies, not UIKit/optical/retail acceptance'}
 if not args.prepare_only:
  assert os.getpriority(os.PRIO_PROCESS,0)==15
  started=time.time();command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(program),'-o',str(out/'scope-tests')]
  with(out/'build.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
  report['compilerExitCode']=r.returncode
  if r.returncode==0:
   r=subprocess.run([str(out/'scope-tests')],capture_output=True,text=True,timeout=30);(out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
  report.update(status='PASS'if r.returncode==0 else'FAIL',seconds=time.time()-started,sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items()))
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'path':str(out),**report}));raise SystemExit(r.returncode or(0 if report['sourcesHeld']else 2))
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'path':str(out),**report}))
if __name__=='__main__':main()
