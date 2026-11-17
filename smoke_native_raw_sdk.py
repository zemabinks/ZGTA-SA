#!/usr/bin/env python3
"""Cross-link immutable raw/coordinator sources and typecheck their real UIKit view; never launch."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/raw-iso-108/sdk-final'
NAMES=['NativeResourceManifest','NativeResourceStore','NativeRawResourceStore','NativeGameSourceInspector','NativeGameFilesCoordinator']
PANEL='''import UIKit
class NativeDEPanelViewController:UIViewController {
 let contentView=UIView();var menuMotionReduced:Bool{false}
 init(title:String){super.init(nibName:nil,bundle:nil)}
 required init?(coder:NSCoder){fatalError()}
 func menuFont(size:CGFloat)->UIFont{.systemFont(ofSize:size)}
 func bodyFont(size:CGFloat)->UIFont{.systemFont(ofSize:size)}
 func menuButton(_ text:String,action:@escaping()->Void)->UIButton{UIButton(type:.system)}
 func registerMenuControl(_ view:UIView,adjust:((Int)->Void)?=nil,activate:(()->Void)?=nil){}
}
'''
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 for platform in ['device','simulator']:
  checked=subprocess.run(['python3',str(ROOT/'build_installer_bridge.py'),'--check','--platform',platform],capture_output=True,text=True)
  if checked.returncode:subprocess.run(['python3',str(ROOT/'build_installer_bridge.py'),'--platform',platform],check=True)
 paths=[ROOT/'ios/App'/str(n+'.swift') for n in NAMES]+[ROOT/'native-installer/swift/NativeISOExtraction.swift',ROOT/'native-installer/swift/NativeRawResourceSelection.swift',ROOT/'ios/App/NativeGameFilesViewController.swift']
 captured={str(p.relative_to(ROOT)):p.read_bytes() for p in paths};results=[]
 with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as folder:
  work=Path(folder)
  for name,data in captured.items():(work/Path(name).name).write_bytes(data)
  sources=[work/str(n+'.swift') for n in NAMES]+[work/'NativeISOExtraction.swift',work/'NativeRawResourceSelection.swift']
  (work/'PanelContract.swift').write_text(PANEL)
  (work/'LinkMain.swift').write_text('import Foundation\n@main struct LinkMain {static func main(){print(NativeRawResourceStore.Snapshot.empty.files);print(NativeGameFilesCoordinator.Kind.extracting.rawValue)}}\n')
  for sdk,targets,archive in [('iphoneos',['arm64-apple-ios16.0'],'device'),('iphonesimulator',['arm64-apple-ios16.0-simulator','x86_64-apple-ios16.0-simulator'],'simulator')]:
   sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
   for target in targets:
    base=['xcrun','--sdk',sdk,'swiftc','-sdk',sdkpath,'-target',target,'-I',str(ROOT/'native-installer/include'),'-module-cache-path',str(OUT/'modules')]
    command=base+['-parse-as-library',*map(str,sources),str(work/'LinkMain.swift'),str(ROOT/'local-only/native-installer'/archive/'libzgtasa_installer.a'),'-lz','-o',str(OUT/('raw-link-'+target))]
    run=subprocess.run(command,capture_output=True,text=True);(OUT/('link-'+target+'.log')).write_text(run.stdout+run.stderr)
    if run.returncode:print(run.stdout+run.stderr);run.check_returncode()
    command=base+['-typecheck',*map(str,sources),str(work/'PanelContract.swift'),str(work/'NativeGameFilesViewController.swift')]
    run=subprocess.run(command,capture_output=True,text=True);(OUT/('view-'+target+'.log')).write_text(run.stdout+run.stderr)
    if run.returncode:print(run.stdout+run.stderr);run.check_returncode()
    results.append({'target':target,'rawCoordinatorSDKLink':'PASS','actualGameFilesViewSDKTypecheck':'PASS','basePanel':'Explicit minimal unrelated menu contract','runtime':'NOT_RUN'});print('PASS raw SDK link/view typecheck',target,flush=True)
 report={'status':'PASS','sourceHashes':{n:hashlib.sha256(v).hexdigest() for n,v in captured.items()},'liveSourcesStillMatch':all((ROOT/n).read_bytes()==v for n,v in captured.items()),'results':results,'limits':['Immutable actual new source snapshot; minimal existing-panel contract only for scoped view typechecking','No full App build, device/Simulator/UI/Files-provider execution, native conversion or playable-installation acceptance']}
 assert report['liveSourcesStillMatch'],'Repeat against a coherent final source boundary'
 (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
