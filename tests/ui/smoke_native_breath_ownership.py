#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual swim/renderer/connection/HUD ownership on authored inputs."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile,time,sys
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from tests.movement.smoke_native_climb_runtime import function
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--negative-root',type=Path);args=parser.parse_args()
os.setpriority(os.PRIO_PROCESS,0,15)
OUT=ROOT/'local-only/research/breath-140';OUT.mkdir(parents=True,exist_ok=True)
paths=[ROOT/'ios/App'/name for name in ['NativeSwimController.swift','NativeWorldRenderer.swift','NativeGameViewController.swift','NativeGameHUD.swift','NativeMultiplayerClient.swift']]
paths +=[Path(__file__).resolve(),Path(__file__).with_suffix('.swift'),ROOT/'selfhost_backend.js',ROOT/'tests/server/smoke_selfhost_breath_lifecycle.js',ROOT/'tests/movement/smoke_native_climb_runtime.py']
if args.negative_root:paths += [args.negative_root/'ios/App/NativeGameViewController.swift',args.negative_root/'ios/App/NativeGameHUD.swift']
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
swim,renderer,vc,hud,network=[p.read_text() for p in paths[:5]]
method=function(renderer,'    func setSelfhostBreathConnection(')
template=Path(__file__).with_suffix('.swift').read_text()
subprocess.run(['node','tests/server/smoke_selfhost_breath_lifecycle.js'],cwd=ROOT,check=True)
health=function(network,'struct NativeHealthPrediction {')
consume=function(network,'private func applyAcknowledgedVitals(').replace('private func','func',1)
variants=[('current',vc,hud,[])]
if args.negative_root:
 oldvc=(args.negative_root/'ios/App/NativeGameViewController.swift').read_text();oldhud=(args.negative_root/'ios/App/NativeGameHUD.swift').read_text()
 variants=[('historical-callback',oldvc,hud,[]),('historical-hud',vc,oldhud,['historical-hud']),*variants]
rows=[]
with tempfile.TemporaryDirectory(prefix='ownership-',dir=OUT)as temporary:
 work=Path(temporary)
 for label,v,h,arguments in variants:
  code='import CoreFoundation\n'+swim+'\n'+health+'\n'+template.replace('// ACTUAL_ACKNOWLEDGED_VITALS',consume).replace('// ACTUAL_BREATH_CONNECTION',method).replace('// ACTUAL_INVENTORY_CALLBACK',function(v,'        network.onInventoryConnection = ')).replace('// ACTUAL_UPDATE_BREATH',function(h,'    func updateBreath(')).replace('// ACTUAL_UPDATE_WORLD',function(h,'    func updateWorld(state:'))
  source=work/(label+'.swift');source.write_text(code);binary=work/label;started=time.monotonic()
  compiled=subprocess.run(['xcrun','swiftc','-O','-whole-module-optimization','-num-threads','1','-module-cache-path',str(OUT/'modules'),str(source),'-o',str(binary)],capture_output=True,text=True,timeout=180)
  (OUT/(label+'-compile.log')).write_text(compiled.stdout+compiled.stderr)
  assert compiled.returncode==0,'Compilation failure is not a historical negative: '+compiled.stderr[-6000:]
  run=subprocess.run([str(binary),*arguments,*(['--server-trace',str(OUT/'server-lifecycle.json')]if label=='current'else[])],capture_output=True,text=True,timeout=30)
  (OUT/(label+'-runtime.log')).write_text(run.stdout+run.stderr)
  expected='fresh selfhost peer oxygen not reset' if label=='historical-callback' else'HTTP snapshot overwrote locally predicted breath'
  if label=='current':assert run.returncode==0 and'PASS breath ownership'in run.stdout,run.stdout+run.stderr
  else:assert run.returncode==2 and expected in run.stdout,run.stdout+run.stderr
  rows.append(dict(label=label,exitCode=run.returncode,seconds=time.monotonic()-started,output=run.stdout,generatedSHA256=hashlib.sha256(code.encode()).hexdigest()))
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==sha for p,sha in hashes.items())
report=dict(status='PASS',results=rows,sourceHashes=hashes,sourceUnchanged=True,actualNice=os.getpriority(os.PRIO_PROCESS,0),scope='Actual swim and extracted renderer/VC/HUD methods; authored UIKit/unrelated owner spies. Real network sockets, scene timing, rendered/hardware/retail acceptance remain separate; actual server ACK packets use authored virtual clocks/files/sockets.')
(OUT/'ownership-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
