#!/usr/bin/env python3
"""Build an asset-free real-UIKit touch ownership carrier; never operate a simulator."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,plistlib,re,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/touch-ownership-106'
METHODS=['private func installHUD()','private func styleControl(','private func button(','private func updateWeaponHUD()','private func setDrivingControls(','private func updateAuxiliaryControls()','@objc private func pressHandbrake()','@objc private func releaseHandbrake()','@objc private func pressBrake()','@objc private func releaseBrake()']
def declaration(source,marker):
 start=source.index(marker);opening=source.index('{',start);depth=1;index=opening+1
 while depth:
  depth+=(source[index]=='{')-(source[index]=='}');index+=1
 return source[start:index]
def sha(data):return hashlib.sha256(data).hexdigest()
def controller(source,name):
 methods='\n'.join(declaration(source,marker) for marker in METHODS)
 # Only the external safe-area fixture is substituted. All production
 # constraints, hierarchy insertion order and visibility assignments survive.
 methods=methods.replace('view.safeAreaLayoutGuide','view.fixtureSafeAreaLayoutGuide')
 selectors=sorted(set(re.findall(r'#selector\((\w+)\)',methods)))
 controls=['vehicleButton','radioButton','missionButton','attackButton','weaponButton','reloadButton','aimButton','crouchButton','runButton','jumpButton','gasButton','brakeButton']
 if 'handbrakeButton' in methods:controls.append('handbrakeButton')
 fields='\n'.join('    private let '+value+'=NativeIconButton()' for value in controls)
 pairs=','.join('("'+value+'",'+value+')' for value in controls)
 actions='\n'.join('    @objc private func '+value+'(){recordedActions.append("'+value+'")} ' for value in selectors if value not in ['pressHandbrake','releaseHandbrake','pressBrake','releaseBrake'])
 return '''final class NAME:UIViewController,ProbeController {
    private let server=ProbeServer(),network=ProbeNetwork(),weapons=ProbeWeapons()
    private let status=UILabel(),players=UILabel(),objective=UILabel(),chatFeed=UILabel(),ammoLabel=UILabel()
    private let gameHUD=ProbeHUD(),mapButton=UIButton(type:.custom),stick=UIView(),lookStick=UIView()
FIELDS
    private var renderer:ProbeRenderer?=ProbeRenderer(),currentVehicle:ProbeVehicle?
    private var auxiliaryMode="",usingPistol=true,usingMelee=false,magazine=12,reserve=80
    private var firePressed=false,gasPressed=false,brakePressed=false,handbrakePressed=false,hornPressed=false,nozzleUpPressed=false,nozzleDownPressed=false
    var recordedActions:[String]=[]
    var acceptsHeldInput=true
    var handbrakeIsHeld:Bool {handbrakePressed}
    var brakeIsHeld:Bool {brakePressed}
    var namedButtons:[(String,UIButton)] {
        var result:[(String,UIButton)]=[PAIRS,("mapButton",mapButton)]
        for button in view.subviews.compactMap({$0 as? UIButton}) where !result.contains(where:{$0.1===button}) {
            result.append((button.accessibilityLabel ?? "unnamed",button))
        }
        return result
    }
    func prepare(_ mode:ProbeMode,_ geometry:ProbeGeometry){
        view=ProbeRootView(size:geometry.size,insets:geometry.insets)
        gameHUD.syntheticWindowSize=geometry.size
        currentVehicle=mode.kind == nil ? nil:ProbeVehicle()
        renderer?.isPassenger=mode.passenger
        renderer?.vehicleKind=mode.kind ?? "car";renderer?.hasVehicleWorkingControls=mode.working
        renderer?.vehicleWorkingIsTow=mode.tow;renderer?.hasJetNozzle=mode.nozzle;renderer?.canUnhitchVehicle=mode.unhitch
        renderer?.hasLandingGear=mode.gear;renderer?.hasVehicleHorn=mode.horn;renderer?.isChuting=mode.deploy
        renderer?.canNativeFootMeleeGuard=mode.guarding;renderer?.supportsFootWeaponAim=mode.pistol
        usingPistol=mode.pistol;usingMelee=mode.melee;weapons.current.supportsAttack=mode.attack
        network.health=mode.dead ? 0:100
        installHUD();setDrivingControls(mode.kind != nil)
        // Production radar is a frame-laid-out child used by map constraints.
        // Re-layout to settle those same cross-view anchors after HUD sizing.
        for _ in 0..<3 {view.setNeedsLayout();view.layoutIfNeeded();gameHUD.setNeedsLayout();gameHUD.layoutIfNeeded()}
        view.layoutIfNeeded()
    }
    private func resetControls(){}
    private func setAiming(_ value:Bool){}
ACTIONS
METHODS
}
'''.replace('NAME',name).replace('FIELDS',fields).replace('PAIRS',pairs).replace('ACTIONS',actions).replace('METHODS',methods)
def verify(path):
 report=json.loads(path.read_text());meta=report['metadata']
 assert report['status']=='PASS',json.dumps(report['current']['failures'],indent=2)
 assert not report['current']['failures'] and report['historicalOverlapHits']>0
 assert len(report['current']['cases'])==18*9,'Matrix coverage changed'
 assert report['current']['checks']>10000,'Insufficient ownership/overlap checks'
 assert meta['controllerSourceSHA256']==sha((ROOT/'ios/App/NativeGameViewController.swift').read_bytes()),'Runtime carrier used another App source'
 assert meta['hudSourceSHA256']==sha((ROOT/'ios/App/NativeGameHUD.swift').read_bytes()),'Runtime carrier used another HUD source'
 assert meta['stickSourceSHA256']==sha((ROOT/'ios/App/NativeVirtualStick.swift').read_bytes()),'Runtime carrier used another stick source'
 assert meta['testSwiftSHA256']==sha((ROOT/'tests/ui/smoke_native_touch_layout.swift').read_bytes()),'Runtime carrier used another test source'
 assert meta['testPythonSHA256']==sha(Path(__file__).read_bytes()),'Runtime carrier used another generator'
 (OUT/'verified-runtime.json').write_text(json.dumps(report,indent=2)+'\n')
 print('PASS real UIKit synthetic-controller runtime:',report['current']['checks'],'checks,',len(report['current']['cases']),'cases,',report['historicalOverlapHits'],'historical overlap hit failures')
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--baseline-source',type=Path,default=ROOT.parent/'ZGTA-SA-core-105/ios/App/NativeGameViewController.swift')
 parser.add_argument('--verify-report',type=Path)
 parser.add_argument('--architectures',nargs='+',choices=['arm64','x86_64'],default=['arm64','x86_64'])
 args=parser.parse_args();OUT.mkdir(parents=True,exist_ok=True)
 if args.verify_report:verify(args.verify_report);return
 currentPath=ROOT/'ios/App/NativeGameViewController.swift';current=currentPath.read_text()
 if args.baseline_source.exists():
  historical=args.baseline_source.read_text();baselineKind='actual Core105 source';baselineHash=sha(historical.encode())
 else:
  # Fresh public clones can still exercise the exact formerly overlapping
  # Jump/Brake frames and z-order, but this is labeled a controlled negative.
  historical=current.replace('jumpButton.isHidden = driving','jumpButton.isHidden = driving && !roadVehicle').replace('handbrakeButton.isHidden = !roadVehicle','handbrakeButton.isHidden = true')
  assert historical!=current
  baselineKind='controlled negative restoring visible driving Jump at unchanged overlapping Brake frame';baselineHash=sha(historical.encode())
 assert 'brakeButton.trailingAnchor.constraint(equalTo: jumpButton.trailingAnchor)' in historical
 assert 'brakeButton.centerYAnchor.constraint(equalTo: jumpButton.centerYAnchor)' in historical
 template=(ROOT/'tests/ui/smoke_native_touch_layout.swift').read_text()
 metadata={'controllerSourceSHA256':sha(current.encode()),'historicalSourceSHA256':baselineHash,'historicalKind':baselineKind,
  'testSwiftSHA256':sha(template.encode()),'testPythonSHA256':sha(Path(__file__).read_bytes()),
  'extraction':'Actual installHUD/style/button/weaponHUD/driving/auxiliary methods; safeAreaLayoutGuide replaced by synthetic-inset guide only',
  'substitutes':['Plain UILabel and UIView stand-ins for non-interactive HUD text and stick display; normal UIKit hitTest bounds match their production non-overridden hit testing',
                'Renderer/network/weapon values are synthetic context fixtures; audio/renderer/network operations are not loaded']}
 icon=declaration(current,'private final class NativeIconButton: UIButton')
 hud=(ROOT/'ios/App/NativeGameHUD.swift').read_text()
 assert 'isUserInteractionEnabled = false; backgroundColor = .clear' in hud,'HUD hit-test policy changed; update the fixture'
 stick=(ROOT/'ios/App/NativeVirtualStick.swift').read_text()
 assert 'override func hitTest' not in stick and 'override func point(' not in stick,'Stick gained custom hit testing; fixture substitution invalid'
 metadata['hudSourceSHA256']=sha(hud.encode());metadata['stickSourceSHA256']=sha(stick.encode())
 radar=re.search(r'        let radarSize: CGFloat = .*\n        radar.frame = .*\n',hud).group(0)
 body=template.replace('// RADAR_LAYOUT',radar).replace('// CONTROLLERS',icon+'\n'+controller(current,'CurrentLayoutController')+'\n'+controller(historical,'HistoricalLayoutController'))
 # JSON is generated as a Swift dictionary from actual JSON bytes, preserving
 # literal hashes and descriptions without shell/string interpolation hazards.
 body=body.replace('import UIKit','import UIKit\nlet probeMetadata = try! JSONSerialization.jsonObject(with: Data(base64Encoded: "'+__import__('base64').b64encode(json.dumps(metadata).encode()).decode()+'")!) as! [String:Any]',1)
 generated=OUT/'main.swift';generated.write_text(body)
 app=OUT/'TouchLayoutProbe.app';app.mkdir(exist_ok=True)
 info={'CFBundleIdentifier':'org.zgtasa.touchlayout106','CFBundleExecutable':'TouchLayoutProbe','CFBundleName':'Touch Layout Probe','CFBundleVersion':'106','CFBundleShortVersionString':'1.0','CFBundlePackageType':'APPL','LSRequiresIPhoneOS':True,'MinimumOSVersion':'16.0','UIDeviceFamily':[1,2],'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UIRequiredDeviceCapabilities':['arm64']}
 (app/'Info.plist').write_bytes(plistlib.dumps(info))
 sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip();binaries=[]
 for arch in args.architectures:
  binary=OUT/('TouchLayoutProbe-'+arch);command=['xcrun','--sdk','iphonesimulator','swiftc','-sdk',sdk,'-target',arch+'-apple-ios16.0-simulator','-module-cache-path',str(OUT/'modules'),'-framework','UIKit',str(generated),'-o',str(binary)]
  run=subprocess.run(command,capture_output=True,text=True);(OUT/('compile-'+arch+'.log')).write_text(run.stdout+run.stderr)
  if run.returncode:print(run.stdout+run.stderr);run.check_returncode()
  binaries.append(binary)
 if len(binaries)>1:subprocess.run(['xcrun','lipo','-create',*map(str,binaries),'-output',str(app/'TouchLayoutProbe')],check=True)
 else:__import__('shutil').copyfile(binaries[0],app/'TouchLayoutProbe');(app/'TouchLayoutProbe').chmod(0o755)
 subprocess.run(['codesign','--force','--sign','-',str(app)],check=True,capture_output=True,text=True)
 report={'status':'BUILT_NOT_RUN','metadata':metadata,'architectures':args.architectures,'app':str(app),'generatedSourceSHA256':sha(generated.read_bytes()),
  'runtimeInstructions':['Only the QA owner should run these; the runner itself never uses simctl.',
   'xcrun simctl install QA_UDID "'+str(app)+'"',
   'xcrun simctl launch --terminate-running-process --console QA_UDID org.zgtasa.touchlayout106',
   'xcrun simctl get_app_container QA_UDID org.zgtasa.touchlayout106 data',
   'python3 tests/ui/smoke_native_touch_layout.py --verify-report DATA_CONTAINER/Documents/touch-layout-report.json']}
 (OUT/'build-report.json').write_text(json.dumps(report,indent=2)+'\n')
 print('BUILT_NOT_RUN:',app);print('Both production App and all devices/simulators remain untouched.')
 print('\n'.join(report['runtimeInstructions']))
if __name__=='__main__':main()
