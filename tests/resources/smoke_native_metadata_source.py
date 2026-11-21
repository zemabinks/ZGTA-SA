#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Literal source/latest metadata admission, with optional actual physical owner."""
from pathlib import Path
import argparse,hashlib,json,os,platform,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
PHYSICS=['WorldCollision','NativeWorldRay','SwiftRapierWorld','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics','NativeVehicleCoupling','NativeRemoteSuspension']
def block(text,marker):
 a=text.index(marker);opening=text.index('{',a);depth=1;b=opening+1
 while depth:depth+=(text[b]=='{')-(text[b]=='}');b+=1
 return text[a:b].replace('private ','')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--historical-root',type=Path);p.add_argument('--with-physics',action='store_true');p.add_argument('--case',choices=['seating','children','physics']);args=p.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
 source=(args.historical_root or ROOT).resolve();out=ROOT/'local-only/research/metadata-source-156'/str(time.time_ns());out.mkdir(parents=True)
 renderer=source/'ios/App/NativeWorldRenderer.swift';text=renderer.read_text();a=text.index('        let modelSource=fixedCJSourceIdentity()',text.index('    func loadModelIndex()'));b=text.index('        loadLegacyStockCatalogs()',a);header=text[a:b]
 cases=[args.case]if args.case else ['seating','children']+(['physics']if args.with_physics else[])
 report=dict(status='RUNNING',source=str(source),historical=bool(args.historical_root),results=[],scope='Literal metadata request/header/admission and actual decoders; authored binding/transport; child effect spies explicit; physical variant uses actual ground/Rapier owner. No rendered, hardware or retail acceptance.')
 def save():(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
 save()
 try:
  for case in cases:
   fixture=Path(__file__).with_name('smoke_native_metadata_'+('source'if case=='seating'else case)+'.swift');harness=fixture.read_text().replace('// ACTUAL_MODEL_REQUEST_HEADER',header)
   if case in ['seating','physics']:
    marker='        NativeResourceTransport.dataTask(with: server.path("game/native/'+('seating.json'if case=='seating'else'vehicles.physics.json')+'"))';a=text.index(marker);b=text.index('        }.resume()',a)+len('        }.resume()');harness=harness.replace('// ACTUAL_'+case.upper()+'_REQUEST',text[a:b])
   else:harness=harness.replace('// ACTUAL_CHILD_METHODS','\n'.join(block(text,'    private func '+name+'()')for name in ['loadVehicleCouplingDefinitions','loadVehicleTreads']))
   if case=='physics':harness=harness.replace('// ACTUAL_CAMERA_DOCUMENTS',block(text,'    private struct CameraVehicleDefinition:')+'\n'+block(text,'    private struct CameraVehicleDocument:'))
   work=out/case;work.mkdir();generated=work/'Gate.swift';generated.write_text(harness)
   paths=[source/'ios/App'/f'{n}.swift'for n in ['ServerAddress',*(['NativeVehicleSeating']if case=='seating'else PHYSICS if case=='physics'else[])]]
   library=ROOT/'local-only/native-physics'/('macos-'+platform.machine());extras=[]
   if case=='physics':
    if 'NativeLocalShots.carTyreCatalog' in text:
     paths += [source/'ios/App'/f'{n}.swift'for n in ['NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots']]
     extras += ['-D','HAS_LOCAL_SHOTS']
    subprocess.run(['python3',str(ROOT/'native-physics/source_stamp.py'),'check',str(library)],check=True)
    pathsForHash=[library/'libzgtasa_native_physics.a'];extras+=['-I',str(ROOT/'native-physics/include'),'-L',str(library),'-lzgtasa_native_physics','-framework','CoreFoundation']
   else:pathsForHash=[]
   frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [*paths,*pathsForHash,fixture,renderer,Path(__file__)]}
   row=dict(case=case,status='RUNNING',sourceHashes=frozen);report['results'].append(row);save()
   command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(work/'modules'),*map(str,paths),str(generated),*extras,'-framework','Security','-o',str(work/'gate')]
   with(work/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=600)
   row['compileExit']=r.returncode
   if r.returncode:row['status']='COMPILE_FAIL';save();print((work/'compile.log').read_text()[-5000:]);r.check_returncode()
   modes=[[],['--same-source-only'],['--source-only'],['--failed-latest']]if case=='seating'else [[],['--source-only']]if case=='physics'else[[]]
   runs=[]
   for mode in modes:
    r=subprocess.run([str(work/'gate'),*mode],capture_output=True,text=True,timeout=90);output=r.stdout+r.stderr;(work/('runtime-'+(mode[0][2:]if mode else'combined')+'.log')).write_text(output);runs.append(dict(mode=mode,exitCode=r.returncode,output=output));print(output,end='')
   row.update(status='PASS'if all(r['exitCode']==0 for r in runs)else'FAIL',runs=runs,sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()));save()
   if row['status']!='PASS' or not row['sourcesHeld']:raise RuntimeError(case+' metadata admission rejected')
  report['status']='PASS';save()
 except BaseException as e:report.update(status='FAIL',error=repr(e));save();raise
 finally:print(json.dumps(dict(status=report['status'],path=str(out),cases=[dict(case=r['case'],status=r['status'],sourcesHeld=r.get('sourcesHeld'))for r in report['results']])))
if __name__=='__main__':main()
