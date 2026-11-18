#!/usr/bin/env python3
"""Asset-free current actor admission and extracted class-menu ownership gate.

Compiles independently authored cases with the production Foundation helper and
actual selected Renderer/GVC methods. It performs no resource/network/UI action.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parent


def extract(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, quoted, escaped = 0, False, False
    for at in range(opening, len(source)):
        character = source[at]
        if quoted:
            if escaped:
                escaped = False
            elif character == '\\':
                escaped = True
            elif character == '"':
                quoted = False
            continue
        if character == '"':
            quoted = True
        elif character == '{':
            depth += 1
        elif character == '}':
            depth -= 1
            if depth == 0:
                return source[start:at + 1].replace('private ', '')
    raise ValueError('Unbalanced Swift production method: ' + marker)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--admission-only', action='store_true', help='Run helper/class gate while Renderer integration is pending')
    parser.add_argument('--historical-root', type=Path, help='Optional read-only older AGPL checkout for the historical race control')
    parser.add_argument('--out', type=Path, default=ROOT / 'local-only/research/actor-selection-115')
    args = parser.parse_args()
    out = args.out.resolve()
    if (ROOT / 'local-only').resolve() not in out.parents:
        raise ValueError('Generated carriers/reports must remain in this checkout local-only')
    out.mkdir(parents=True, exist_ok=True)
    paths = ['ios/App/NativeActorSelection.swift', 'ios/App/NativeGameViewController.swift',
             'ios/App/NativeWorldRenderer.swift', 'smoke_native_actor_selection.py', 'smoke_native_actor_selection.swift',
             'ios/App/NativeSAMPSkinCatalog.swift']
    inputs = {name: (ROOT / name).read_bytes() for name in paths}
    vc = inputs[paths[1]].decode()
    renderer = inputs[paths[2]].decode()
    methods = '\n\n'.join(extract(vc, marker) for marker in [
        'private func showLegacyClass(', 'private var legacyClassArtworkReady:',
        'private func legacyClassCanSpawn(', 'private func legacyClassMessage(',
        'private func updateLegacyClassAdmission(', 'private func actorSelectionChanged(',
        'private func requestLegacyClassSpawn('])
    source = inputs[paths[5]].decode() + '\n' + inputs[paths[4]].decode().replace('// ACTUAL_CLASS_METHODS', methods)
    renderer_checks = ''
    if not args.admission_only:
        renderer_checks = renderer_carrier(renderer)
    source = source.replace('// ACTUAL_RENDERER_CHECKS', renderer_checks)
    (out / 'main.swift').write_text(source)
    helper = out / 'NativeActorSelection.swift'
    helper.write_bytes(inputs[paths[0]])
    command = ['xcrun', 'swiftc', '-Onone', '-swift-version', '5', '-module-cache-path', str(out / 'modules'),
               str(helper), str(out / 'main.swift'), '-o', str(out / 'verify')]
    compiled = subprocess.run(command, text=True, capture_output=True)
    (out / 'compile.log').write_text(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        print(compiled.stdout + compiled.stderr)
    compiled.check_returncode()
    result = subprocess.run([str(out / 'verify')], text=True, capture_output=True, timeout=20)
    (out / 'runtime.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, end='')
    result.check_returncode()
    matched = re.search(r'actor-selection PASS (\d+)', result.stdout)
    assert matched, 'Actual carrier did not finish its assertions'
    unchanged = all((ROOT / name).read_bytes() == value for name, value in inputs.items())
    assert unchanged, 'Source changed while the immutable gate ran'
    # These are integration callsite assertions, not a substitute for the
    # executable admission/activation cases above.
    for snippet in [
        'renderer.onActorSelectionChanged =',
        'legacyClassSkin=nil;renderer?.cancelActorSelection()',
        'if let skin=staff.skin{_=renderer?.setLocalSkin(skin);network.setLocalSkin(skin)}',
        '_=renderer?.setLocalSkin(skin);network.setLocalSkin(skin);if let note{status.text=note}',
    ]:
        assert snippet in vc, 'Canonical identity or lifecycle wiring changed: ' + snippet
    report = {'status': 'PASS', 'scope': 'helper/class-admission-only' if args.admission_only else 'helper/class/actual-renderer',
              'checks': int(matched.group(1)), 'sourceUnchanged': unchanged,
              'sourceHashes': {name: hashlib.sha256(data).hexdigest() for name, data in inputs.items()},
              'extractedClassSHA256': hashlib.sha256(methods.encode()).hexdigest(),
              'limits': ['Authored metadata and synchronous UI boundaries; no actual UIKit presentation or GPU operation',
                         'Nonzero applied means verified catalogue/renderer identity admission, not completed mesh upload',
                         'CJ availability is a controlled ready flag here; actual CJ GPU/parser acceptance is separate',
                         'Server canonical staff/dress and legacy identity protocols are unchanged']}
    if args.historical_root:
        report['historical'] = historical_control(args.historical_root.resolve(), out)
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def renderer_carrier(source):
    selection = source[source.index('    private let actorSelection = NativeActorSelection()'):
                       source.index('    private var weaponModels:')].replace('private ', '')
    ready = extract(source, 'owner.onReady=')
    assert 'self.resumeActorSelection()' in ready and 'ready.sourceIdentity==self.fixedCJSourceIdentity()' in ready
    assert 'setLocalSkin(' not in ready and 'setLegacySkin(' not in ready, 'Completion starts a fresh request'
    assert '_ = self.actorSelection.invalidateSource(self.fixedCJSourceIdentity())' in source
    assert 'actorSelection.cancel();fixedCJ?.reset()' in source
    assert '_=fixedCJ?.ensure(force:force)' in extract(source, 'private func ensureFixedCJ(')
    return r'''
final class SelectionCJ {var isReady=false}
final class SelectionVisibility {var resets=0;func reset(){resets+=1}}
final class SelectionRenderer {
    var source="source-a",localSkin=7,localLegacySkin:Int?
    var pedModels:[String:String]=[:],legacyPedModels:[String:Int]=[:]
    var fixedCJ:SelectionCJ?=SelectionCJ()
    var ownRiderCapture:Int?=1,ownRiderPrevious:Int?=2,ownRiderFeet:Int?=3
    let ownCameraVisibility=SelectionVisibility()
    var ensures=0,forces:[Bool]=[],loaded:[String]=[],prepared=0,onStatus:((String)->Void)?
    func fixedCJSourceIdentity()->String{source}
    func ensureFixedCJ(force:Bool=false){ensures+=1;forces.append(force)}
    func loadActor(_ model:String){loaded.append(model)}
    func prepareFootAnimation(){prepared+=1}
    SELECTION
    // Authored readiness boundary; only the production resolver decides which
    // current intent to apply. No CJ bytes or Metal success are fabricated.
    func arriveCJ(){fixedCJ!.isReady=true;pedModels["0"]="null";resumeActorSelection()}
}
func rendererChecks() {
    let catalogue=try! JSONSerialization.data(withJSONObject:["schema":1,"skins":[
        ["legacyID":3,"nativeID":3,"model":"authored_three"],
        ["legacyID":5,"nativeID":14,"model":"authored_five"],
        ["legacyID":6,"nativeID":NSNull(),"model":"unavailable"]]])
    for next in [3,5,20001] {
        let owner=SelectionRenderer()
        var states:[NativeActorSelection.State]=[]
        owner.onActorSelectionChanged={states.append($0)}
        check(!owner.setLocalSkin(0) && owner.pendingLocalSkin==0,"CJ request did not wait")
        let first=owner.actorSelectionState!.request
        check(!owner.setLegacySkin(next) && owner.pendingLegacySkin==next && owner.pendingLocalSkin==nil,"Two pending domains survived supersession")
        let current=owner.actorSelectionState!.request
        owner.arriveCJ()
        check(owner.localSkin==7 && owner.pendingLegacySkin==next && owner.loaded.isEmpty,"Earlier CJ completion replaced newer legacy intent")
        check(owner.actorSelectionState?.request==current,"Resource arrival replaced the request token")
        check(!owner.actorSelection.applied(first,nativeSkin:0,sourceIdentity:owner.source),"Old token admitted after later readiness")
        owner.pedModels["3"]="authored_three";owner.pedModels["14"]="authored_five"
        if next==20001{owner.pedModels["20001"]="samp-dl-20001";owner.legacyPedModels["samp-dl-20001"]=1}
        check(owner.loadLegacySkinCatalog(catalogue),"Authored exact catalogue did not parse")
        let expected=next==5 ? 14:next
        check(owner.localSkin==expected && owner.localLegacySkin==next,"Latest native/legacy mapping did not commit")
        check(owner.actorSelectionState?.phase == .applied && owner.actorSelectionState?.request==current,"Latest admission identity changed during resume")
        check(owner.pendingLocalSkin==nil && owner.pendingLegacySkin==nil,"Terminal selection retained pending intent")
        let count=states.count,loads=owner.loaded.count
        owner.resumeActorSelection();owner.arriveCJ()
        check(states.count==count && owner.loaded.count==loads,"Duplicate completion reapplied terminal selection")
    }
    for next in [-1,312,999,20000,30001,65536] {
        let owner=SelectionRenderer();_=owner.setLocalSkin(0)
        check(!owner.setLegacySkin(next) && owner.actorSelectionState?.phase == .unavailable,"Invalid newer legacy request was not terminal")
        owner.arriveCJ()
        check(owner.localSkin==7 && owner.pendingLocalSkin==nil && owner.pendingLegacySkin==nil,"Unsupported newer request revived old CJ intent")
    }
    do {
        let owner=SelectionRenderer();_=owner.setLegacySkin(0)
        _=owner.setLocalSkin(3);owner.arriveCJ()
        check(owner.actorSelectionState?.phase == .unavailable && owner.localSkin==7 && owner.localLegacySkin==nil,"New native unsupported catalogue row applied old legacy CJ")
        owner.pedModels["3"]="authored_three"
        check(owner.setLocalSkin(3) && owner.localSkin==3 && owner.localLegacySkin==nil,"Explicit native retry did not recover")
        check(owner.loaded==["authored_three"] && owner.prepared==1 && owner.ownRiderCapture==nil && owner.ownCameraVisibility.resets==1,"Normal commit/capture cleanup changed")
        check(owner.setLocalSkin(3) && owner.prepared==1 && owner.ownCameraVisibility.resets==1,"Same identity unnecessarily reset motion/skeleton captures")
    }
    do {
        let owner=SelectionRenderer();owner.pedModels=["3":"authored_three"]
        _=owner.loadLegacySkinCatalog(catalogue)
        check(owner.setLegacySkin(3),"Ready legacy model did not commit")
        owner.source="source-b"
        check(owner.actorSelectionState==nil,"Stored old-source admission enabled SPAWN before observer delivery")
        check(owner.actorSelection.invalidateSource(owner.source),"Source invalidation did not cancel")
        owner.resumeActorSelection()
        check(owner.loaded.count==1 && owner.actorSelectionState==nil,"Source invalidation reissued an old request")
        check(owner.setLegacySkin(3) && owner.actorSelectionState?.request.sourceIdentity=="source-b","Explicit new-source retry failed")
    }
    do {
        let owner=SelectionRenderer();_=owner.setLocalSkin(0)
        let request=owner.actorSelectionState!.request
        owner.cancelActorSelection();owner.arriveCJ()
        check(owner.localSkin==7 && owner.actorSelectionState?.phase == .cancelled,"Late CJ completion undid lifecycle cancellation")
        check(!owner.actorSelection.applied(request,nativeSkin:0,sourceIdentity:owner.source),"Cancelled token reused")
        check(owner.setLegacySkin(0) && owner.localSkin==0 && owner.localLegacySkin==0,"Explicit ready-CJ legacy request did not apply")
    }
    do {
        let owner=SelectionRenderer();owner.pedModels=["3":"authored_three"]
        var superseded=false
        owner.onActorSelectionChanged={state in
            if !superseded && state.request.skin==0 && state.phase == .pending {
                superseded=true;_=owner.setLocalSkin(3)
            }
        }
        check(!owner.setLocalSkin(0) && owner.localSkin==3 && owner.pendingLocalSkin==nil,"Reentrant newer request was overwritten by outer setter")
        check(owner.ensures==0,"Superseded outer request still forced a CJ load")
        owner.arriveCJ()
        check(owner.localSkin==3 && owner.loaded==["authored_three"],"Late arrival revived reentrantly superseded request")
    }
    do {
        let owner=SelectionRenderer();_=owner.setLocalSkin(0)
        let requested=owner.actorSelectionState!.request
        owner.source="source-b";owner.arriveCJ()
        check(owner.localSkin==7 && owner.pendingLocalSkin==nil && owner.actorSelection.state?.phase == .cancelled,"Resolver admitted an old-source intent")
        check(!owner.actorSelection.unavailable(requested,sourceIdentity:owner.source,message:"late error"),"Old-source error overwrote cancellation")
    }
    do {
        let owner=SelectionRenderer()
        check(!owner.setLocalSkin(0) && owner.forces==[true],"Explicit native CJ request did not bypass prior cooldown")
        owner.resumeActorSelection()
        check(owner.forces==[true,false],"Async resumption forced a background retry")
        let failed=owner.actorSelectionState!.request
        _=owner.actorSelection.unavailable(failed,sourceIdentity:owner.source,message:"authored unavailable resource")
        owner.resumeActorSelection()
        check(owner.forces==[true,false],"Terminal failure silently retried in background")
        check(!owner.setLegacySkin(0) && owner.forces==[true,false,true],"Normal new legacy CJ selection remained in silent cooldown")
        check(owner.actorSelectionState?.phase == .pending && owner.localSkin==7 && owner.loaded.isEmpty,"Retry fabricated admission or altered drawn identity")
        owner.cancelActorSelection();owner.resumeActorSelection()
        check(owner.forces==[true,false,true],"Cancelled request forced work")
    }
    for ready in [false,true] {
        for domain in [NativeActorSelection.Domain.native,.legacy] {
            let owner=SelectionRenderer();owner.fixedCJ!.isReady=ready
            owner.pedModels["0"]="conflicting_source_model"
            let accepted=domain == .native ? owner.setLocalSkin(0):owner.setLegacySkin(0)
            check(!accepted && owner.actorSelectionState?.phase == .unavailable,"Conflicting CJ row waited forever or admitted another model")
            check(owner.actorSelectionState?.message?.contains("CONFLICTS")==true && owner.ensures==0 && owner.localSkin==7,"Conflicting catalogue forced work or changed local identity")
        }
    }
}
rendererChecks()
'''.replace('SELECTION', selection)


def historical_control(root, out):
    path = root / 'ios/App/NativeWorldRenderer.swift'
    source = path.read_text()
    methods = '\n'.join(extract(source, marker) for marker in [
        '@discardableResult func loadLegacySkinCatalog(',
        '@discardableResult func setLegacySkin(', '@discardableResult func setLocalSkin('])
    start = source.index('if self.pendingLegacySkin==0{_=self.setLegacySkin(0)}')
    end = source.index('if self.localSkin==0{', start)
    callback = source[start:end]
    code = r'''
import Foundation
final class NativeSAMPSkinCatalog {
    init(data: Data) throws {}
    func nativeSkin(forLegacy id: Int) -> Int? { id == 3 ? 3 : nil }
    func model(forLegacy id: Int) -> String? { id == 3 ? "authored_three" : nil }
}
final class CJ { var isReady = false }
final class Visibility {func reset(){}}
final class Historical {
    var localSkin=7,pendingLocalSkin:Int?,localLegacySkin:Int?,pendingLegacySkin:Int?
    var pedModels:[String:String]=[:],legacyPedModels:[String:Int]=[:]
    var sampSkinCatalog:NativeSAMPSkinCatalog?,fixedCJ:CJ?=CJ()
    var onStatus:((String)->Void)?,ownRiderCapture:Int?,ownRiderPrevious:Int?,ownRiderFeet:Int?
    let ownCameraVisibility=Visibility()
    func ensureFixedCJ(){}
    func loadActor(_ name:String){}
    func prepareFootAnimation(){}
    METHODS
    func cjReady(){fixedCJ!.isReady=true;pedModels["0"]="null";CALLBACK}
}
var cases=0
for newer in [3,20001,999] {
    let owner=Historical()
    _=owner.setLocalSkin(0)
    _=owner.setLegacySkin(newer)
    precondition(owner.pendingLocalSkin==0,"Historical pending-CJ precondition changed")
    if newer != 999 {precondition(owner.pendingLegacySkin==newer,"Historical legacy-wait precondition changed")}
    owner.cjReady()
    precondition(owner.localSkin==0 && owner.pendingLegacySkin==nil,"Expected historical supersession defect was not reproduced")
    cases+=1
}
// Negative control: an already available ordinary model takes the success
// branch, which clears the old pending native request even in the old source.
let ready=Historical();ready.pedModels["3"]="authored_three"
_=ready.loadLegacySkinCatalog(Data());_=ready.setLocalSkin(0);_=ready.setLegacySkin(3);ready.cjReady()
precondition(ready.localSkin==3 && ready.localLegacySkin==3,"Historical ready-model negative control failed")
cases+=1
print("historical-supersession REPRODUCED \(cases)")
'''.replace('METHODS', methods).replace('CALLBACK', callback)
    historical = out / 'historical'
    historical.mkdir(exist_ok=True)
    carrier = historical / 'main.swift'
    carrier.write_text(code)
    command = ['xcrun', 'swiftc', '-Onone', '-swift-version', '5', '-module-cache-path', str(out / 'modules'),
               str(carrier), '-o', str(historical / 'verify')]
    compiled = subprocess.run(command, capture_output=True, text=True)
    (historical / 'compile.log').write_text(compiled.stdout + compiled.stderr)
    compiled.check_returncode()
    ran = subprocess.run([str(historical / 'verify')], capture_output=True, text=True, timeout=10)
    (historical / 'runtime.log').write_text(ran.stdout + ran.stderr)
    ran.check_returncode()
    assert 'historical-supersession REPRODUCED 4' in ran.stdout
    return {'status': 'HISTORICAL_DEFECT_REPRODUCED', 'cases': 4,
            'rendererSHA256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'methodsSHA256': hashlib.sha256(methods.encode()).hexdigest(),
            'callbackSHA256': hashlib.sha256(callback.encode()).hexdigest(),
            'scope': 'Actual older AGPL setters and CJ completion decision; authored catalogue/ready boundaries only'}


if __name__ == '__main__':
    main()
