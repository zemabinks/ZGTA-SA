#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual visible HUD update and weapon-icon retry owner, authored boundaries."""
from pathlib import Path
import argparse,hashlib,json,subprocess,os,time,sys
ROOT=Path(__file__).resolve().parents[2]
base=ROOT/'local-only/research/hud-icon-polling';base.mkdir(parents=True,exist_ok=True);owner=ROOT
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=owner);p.add_argument('--expect-old',action='store_true');args=p.parse_args();root=args.root.resolve()
assert os.getpriority(os.PRIO_PROCESS,0)==15
sys.path.insert(0,str(root));from tests.ui.smoke_native_weapon_icons import block
hud=root/'ios/App/NativeGameHUD.swift';controller=root/'ios/App/NativeGameViewController.swift';fixture=root/'tests/ui/smoke_native_weapon_icons.swift';s=hud.read_text();start=s.index('final class NativeGameHUD:');s=s[start:]
fields=s[s.index('    private var weapon'):s.index('    private var wantedLevel')].replace('private ','')
methods=block(s,'    private func weaponIconSource(')+'\n'+block(s,'    func loadWeaponIcon(')+'\n'+block(s,'    deinit ')
c=controller.read_text();start=c.index('        if link.timestamp - lastHUD > 0.1, let renderer {');end=c.index('            status.expireIfNeeded()',start);prefix=c[start:end]+'        }'
code=fixture.read_text().split('@main private enum Main {')[0].replace('// ACTUAL_FIELDS',fields).replace('// ACTUAL_METHODS',methods)
code+='''
private final class Radar{func loadMap(server:ServerAddress){}}
private extension HUD{var radar:Radar{Radar()};func loadFont(server:ServerAddress){}}
private final class Renderer{}
private struct Weapons{var selected=0}
private struct Link{let timestamp:Double}
private final class Controller{
 let server=ServerAddress("http://authored.invalid"),gameHUD=HUD(),renderer:Renderer?=Renderer(),weapons=Weapons()
 var lastHUD=0.0
 func tick(_ timestamp:Double){let link=Link(timestamp:timestamp)
'''+prefix+'''
 }
}
@main private enum Probe{
 static func drain(_ seconds:Double){let end=Date().addingTimeInterval(seconds);while Date()<end{_ = RunLoop.current.run(mode:.default,before:min(end,Date().addingTimeInterval(0.01)))}}
 static func main(){
  let c=Controller();c.gameHUD.loadWeaponIcon(server:c.server,weapon:0)
  guard NativeResourceTransport.requests.count==1 else{fatalError("Initial request missing")}
  NativeResourceTransport.requests[0].finish(nil,status:503);drain(0.1);drain(2.05)
  for n in 1...40{c.tick(Double(n)*0.2)}
  guard NativeResourceTransport.requests.count==2 else{
   FileHandle.standardError.write(Data("FAIL visible idle HUD never invokes the existing icon retry after its backoff\\n".utf8));exit(42)
  }
  NativeResourceTransport.requests[1].finish("recovered-fist");drain(0.1)
  guard c.gameHUD.weaponIcon.image?.value=="recovered-fist" else{fatalError("Recovered icon did not publish")}
  for n in 41...80{c.tick(Double(n)*0.2)}
  guard NativeResourceTransport.requests.count==2 else{fatalError("Ready icon repeatedly refetched by the visible HUD tick")}
  print("PASS actual idle HUD prefix plus actual icon owner: retry recovers and loaded/in-flight polls deduplicate; explicit image/store/radar/font boundaries, no UIKit/App/network/retail claim")
 }
}
'''
paths=[hud,controller,fixture,Path(__file__).resolve()];frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths};out=base/str(time.time_ns());out.mkdir();(out/'Gate.swift').write_text(code)
report=dict(status='RUNNING',startedAt=time.time(),root=str(root),expectHistoricalFailure=args.expect_old,inputHashes=frozen,scope='Literal actual visible HUD tick prefix and complete actual icon fields/source/load/deinit, with explicitly inert image/transport/store/radar/font/controller interfaces. Real main-queue and monotonic retry. No UIKit, real asset, socket, App or retail comparison.')
def save():
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(base/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
save()
try:
 r=subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(out/'Gate.swift'),'-o',str(out/'gate')],capture_output=True,text=True,timeout=240);(out/'compile.log').write_text(r.stdout+r.stderr);report['compileExit']=r.returncode;save();assert r.returncode==0,r.stderr[-4000:]
 r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=15);(out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
 if args.expect_old:assert r.returncode==42 and 'visible idle HUD never invokes'in r.stderr,r.stdout+r.stderr;report['status']='EXPECTED_OLD_ICON_RETRY_CALLER_FAILURE'
 else:assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
except BaseException as e:report.update(status='FAIL',error=repr(e));raise
finally:
 report.update(inputsHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),completedAt=time.time());save();print(json.dumps({k:v for k,v in report.items()if k!='inputHashes'},indent=2))
