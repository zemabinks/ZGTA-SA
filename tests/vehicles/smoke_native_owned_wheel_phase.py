#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual solver/owner handoffs with authored resources; no live application."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,os,platform,subprocess,time
from tests.vehicles.smoke_native_vehicle_presentation import declaration
from tests.vehicles.smoke_native_parked_phase import NAMES
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--historical-root',type=Path);p.add_argument('--prepare-only',action='store_true');args=p.parse_args()
 os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/owned-wheel-phase-130'/str(time.time_ns());out.mkdir(parents=True)
 library=ROOT/('local-only/native-physics/macos-'+platform.machine())/'libzgtasa_native_physics.a';assert library.is_file()
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 paths=[ROOT/'ios/App'/(n+'.swift') for n in NAMES]+[ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'tests/vehicles/smoke_native_owned_wheel_phase.swift',Path(__file__).resolve(),library]
 variants=([('historical',args.historical_root.resolve())] if args.historical_root else [])+[('current',ROOT)]
 if args.historical_root:paths += [args.historical_root/'ios/App'/(n+'.swift') for n in ['NativeGroundVehicle','NativeOtherVehicles','NativeWorldRenderer']]
 frozen={str(p):sha(p) for p in paths};results=[]
 for label,root in variants:
  work=out/label;work.mkdir();sources=[]
  for name in NAMES:
   source=(root if name in ['NativeGroundVehicle','NativeOtherVehicles'] else ROOT)/'ios/App'/(name+'.swift');text=source.read_text()
   if label=='historical':
    if name=='NativeGroundVehicle':
     assert 'func restoreWheelSpin(' not in text
     # Interface only; old parking/entry/solver behavior stays literal.
     text+='\nextension NativeGroundVehicle{func restoreWheelSpin(front:Double,rear:Double){}}\n'
   dest=work/(name+'.swift');dest.write_text(text);sources.append(str(dest))
  renderer=(root/'ios/App/NativeWorldRenderer.swift').read_text()
  if label=='historical':
   getter='private var ownVehicleWheelClocks:[Double]{groundVehicle.wheelAnglesDouble}'
   entry='if groundVehicle.enter(model:activeVehicleModel,modelPosition:camera,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll,bodyPose:pendingVehicleSnapshot?.physicalPose){pendingVehicleSnapshot=nil}'
  else:
   getter=declaration(renderer,'    private var ownVehicleWheelClocks:')
   # Optional chaining only adapts the carrier's nonoptional actual manager.
   getter=getter.replace('groundVehicle?.active == true','groundVehicle.active').replace('groundVehicle?.wheelAnglesDouble ?? []','groundVehicle.wheelAnglesDouble')
   entry=declaration(renderer,'                if groundVehicle.enter(model:activeVehicleModel,')
  text=(ROOT/'tests/vehicles/smoke_native_owned_wheel_phase.swift').read_text().replace('// ACTUAL_COUNTER_GETTER',getter).replace('// ACTUAL_ENTRY_HANDOFF',entry)
  contexts=[]
  for name in ['OwnVehicleDrawSnapshot','ParkedVehicleDrawSnapshot','VehicleDrawContext']:
   value=declaration(renderer,'    private struct '+name+' {')
   if label=='historical' and name=='OwnVehicleDrawSnapshot':
    # Interface field only; historical raw selector remains unchanged.
    value=value[:-1]+'var wheelPhaseOwned=false\n}'
   contexts.append(value)
  text=text.replace('// ACTUAL_RAW_CONTEXT','\n'.join(contexts)).replace('// ACTUAL_RAW_SELECTOR',declaration(renderer,'    private static func legacyVehicleWheel('))
  assert '// ACTUAL_' not in text
  main=work/'Gate.swift';main.write_text(text);sources.append(str(main));exe=work/'verify'
  cmd=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,'-L',str(library.parent),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(exe)]
  row={'label':label,'command':cmd};results.append(row)
  if args.prepare_only:continue
  started=time.monotonic();built=subprocess.run(cmd,capture_output=True,text=True,timeout=600);(work/'compile.log').write_text(built.stdout+built.stderr);built.check_returncode()
  ran=subprocess.run([str(exe),label],capture_output=True,text=True,timeout=120);(work/'runtime.log').write_text(ran.stdout+ran.stderr);row.update(exitCode=ran.returncode,seconds=time.monotonic()-started,output=ran.stdout)
  if label=='historical':assert ran.returncode==2 and 'owned park lost front wheel phase' in ran.stdout,row
  else:assert ran.returncode==0 and 'PASS' in ran.stdout,row
 assert all(sha(Path(p))==h for p,h in frozen.items())
 report={'status':'PREPARED_NOT_COMPILED' if args.prepare_only else 'PASS','sourceUnchanged':True,'sourceHashes':frozen,'results':results,'scope':'Actual native physics/owned/parked managers with authored definitions/floor; literal renderer entry branch and counter getter with optional-carrier adaptation. No live app, GPU, network or retail acceptance.'}
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'results':[{k:r[k]for k in ['label','exitCode','seconds','output']if k in r}for r in results],'output':str(out)},indent=2))
if __name__=='__main__':main()
