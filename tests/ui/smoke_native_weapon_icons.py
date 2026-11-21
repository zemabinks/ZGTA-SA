#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Execute actual HUD icon request ownership with explicit image/transport spies."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def block(source,marker):
 a=source.index(marker);b=source.index('{',a)+1;depth=1
 while depth:depth+=(source[b]=='{')-(source[b]=='}');b+=1
 return source[a:b].replace('private ','')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path);p.add_argument('--prepare-only',action='store_true');args=p.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
 current=ROOT/'ios/App/NativeGameHUD.swift';selected=(args.source or current).resolve();source=selected.read_text();start=source.index('final class NativeGameHUD:');end=source.index('{',start)+1;depth=1
 while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
 hud=source[start:end]
 declarations=hud[hud.index('    private var weapon'):hud.index('    private var wantedLevel')].replace('private ','')
 methods=block(hud,'    func loadWeaponIcon(')
 if '    private func weaponIconSource('in hud:methods=block(hud,'    private func weaponIconSource(')+'\n'+methods
 if '    deinit {'in hud:methods+='\n'+block(hud,'    deinit ')
 fixture=Path(__file__).with_suffix('.swift');code=fixture.read_text().replace('// ACTUAL_FIELDS',declarations).replace('// ACTUAL_METHODS',methods)
 out=ROOT/'local-only/research/weapon-icons-173'/str(time.time_ns());out.mkdir(parents=True)
 paths=[current,selected,fixture,Path(__file__).resolve()];frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
 report=dict(status='PREPARED',startedAt=time.time(),sourceHashes=frozen,source=str(selected),historicalSource=bool(args.source),scope='Actual HUD request fields/source identity/loader/destructor. Explicit authored decoded-image, transport, resource-binding and server-address boundaries; real main-queue callbacks/monotonic retry. No UIKit pixels, assets, network, App or retail acceptance')
 def save():
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
 save()
 try:
  (out/'Gate.swift').write_text(code)
  if not args.prepare_only:
   with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(out/'Gate.swift'),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=240)
   report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-4000:]
   r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=30);report.update(exitCode=r.returncode,output=r.stdout+r.stderr);save();assert r.returncode==0,report['output'];report['status']='PASS'
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:
  report.update(sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),completedAt=time.time());save();print({k:v for k,v in report.items()if k!='sourceHashes'})
if __name__=='__main__':main()
