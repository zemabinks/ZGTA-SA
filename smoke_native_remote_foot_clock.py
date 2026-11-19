#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual CPU CLP/remote animation clock; authored tracks, no original assets."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, tempfile, time

ROOT = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-root', type=Path)
    parser.add_argument('--owned-library', type=Path)
    parser.add_argument('--owned-definitions', type=Path)
    args = parser.parse_args()
    os.setpriority(os.PRIO_PROCESS, 0, 15)
    out = ROOT/'local-only/research/remote-foot-clock-121'
    out.mkdir(parents=True, exist_ok=True)
    names = ['NativeSkeletalActor', 'NativeGunAnimation', 'NativeSwimAnimation',
             'NativeFlightAnimation', 'NativeFootAnimation', 'NativePedestrianReaction',
             'NativeRemoteFootAnimation', 'NativeWorldRenderer']
    paths = [ROOT/'ios/App'/(n+'.swift') for n in names]
    paths += [Path(__file__).resolve(), ROOT/'smoke_native_remote_foot_clock.swift']
    if args.owned_library: paths.append(args.owned_library.resolve())
    if args.owned_definitions:
        assert args.owned_library, '--owned-definitions requires --owned-library'
        paths.append(args.owned_definitions.resolve())
    before = {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    actor = paths[0].read_text()
    # The real decoder and real aim value type, without any Metal actor code.
    common = actor[:actor.index('struct NativeSkinVertex')].replace('import Metal','')
    common += '\nfinal class NativeSkeletalActor {\n'+actor[actor.index('    struct OriginalAim {'):actor.index('    struct Pose {')]+'}\n'
    for path in paths[1:6]: common += '\n'+path.read_text()
    renderer = paths[7].read_text()
    assert 'animator.update(delta:riderDelta,nowMilliseconds:riderTime*1000,snapshot:state)' not in renderer
    assert 'cached.1.resetDisplayClock()' in renderer
    assert 'sampledRemoteFootIDs.insert(player.id)' in renderer
    start = renderer.index('animator.update(at:riderTime,')
    end = renderer.index('snapshot:state)', start)+len('snapshot:state)')
    call = renderer[start:end].replace('animator.', 'engine.').replace('riderTime', 'time')
    call = call.replace('UIApplication.shared.applicationState == .active && view.window != nil', 'active')
    assert 'UIApplication' not in call
    canopy_start = renderer.index('        let targets=canopySamples.isEmpty ? [flight.canopy]:canopySamples')
    canopy_end = renderer.index('        if let canopy=flight.canopy,let posed=',canopy_start)
    canopy_dispatch = renderer[canopy_start:canopy_end]
    harness = paths[9].read_text().replace('// ACTUAL_CANOPY_DISPATCH',canopy_dispatch)
    results = []
    with tempfile.TemporaryDirectory(prefix='gate-',dir=out) as directory:
        work = Path(directory)
        def run(label, remote, adapter):
            source = common+'\n'+remote+'\n'+adapter+'\n'+harness
            p = work/(label+'.swift');p.write_text(source)
            binary = work/label
            command = ['xcrun','swiftc','-O','-whole-module-optimization','-num-threads','1',
                       '-module-cache-path',str(out/'modules'),str(p),'-o',str(binary)]
            started = time.monotonic()
            built = subprocess.run(command,capture_output=True,text=True,timeout=240)
            (out/(label+'-compile.log')).write_text(built.stdout+built.stderr)
            if built.returncode: raise RuntimeError(label+' compilation failed; see retained log')
            command = [str(binary),label]+([str(args.owned_library)] if args.owned_library else [])
            if args.owned_definitions: command.append(str(args.owned_definitions))
            executed = subprocess.run(command,capture_output=True,text=True,timeout=60)
            (out/(label+'-runtime.log')).write_text(executed.stdout+executed.stderr)
            row = dict(label=label,exitCode=executed.returncode,seconds=time.monotonic()-started,
                       generatedSourceSHA256=hashlib.sha256(source.encode()).hexdigest(),output=executed.stdout)
            results.append(row)
            if label=='historical':
                assert executed.returncode==2 and 'elapsed root travel lost' in executed.stdout,row
            else: assert executed.returncode==0 and 'PASS' in executed.stdout,row
        if args.negative_root:
            old = args.negative_root.resolve()/'ios/App'
            text = (old/'NativeWorldRenderer.swift').read_text()
            cap = next(l.strip() for l in text.splitlines() if 'let riderDelta = lastRiderDraw > 0' in l)
            adapter = '''final class DrawOwner {
                let engine:NativeRemoteFootAnimation
                var lastRiderDraw:Double=0
                init(_ engine:NativeRemoteFootAnimation){self.engine=engine}
                func reset(){lastRiderDraw=0}
                func sample(_ time:Double,_ active:Bool,_ state:NativeRemoteFootAnimation.Snapshot)->NativeFootAnimation.Frame? {
                    let riderTime=time
                    CAP
                    lastRiderDraw=riderTime
                    return engine.update(delta:riderDelta,nowMilliseconds:time*1000,snapshot:state)
                }
            }'''.replace('CAP',cap)
            run('historical',(old/'NativeRemoteFootAnimation.swift').read_text(),adapter)
        adapter = '''final class DrawOwner {
            let engine:NativeRemoteFootAnimation
            init(_ engine:NativeRemoteFootAnimation){self.engine=engine}
            func reset(){engine.resetDisplayClock()}
            func sample(_ time:Double,_ active:Bool,_ state:NativeRemoteFootAnimation.Snapshot)->NativeFootAnimation.Frame? {
                return CALL
            }
        }'''.replace('CALL',call)
        run('current',paths[6].read_text(),adapter)
    assert before=={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in before}
    report=dict(status='PASS',results=results,sourceUnchanged=True,sourceHashes=before,
                actualNice=os.getpriority(os.PRIO_PROCESS,0),literalRendererCall=call,
                literalCanopyDispatch=canopy_dispatch,
                scope='Actual CLP decoder, gun/swim/flight/foot/reaction/remote code; authored tracks. Optional owned library is private CPU evidence only.',
                noGPUOrLiveWorldOrRetailClaim=True)
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['status','actualNice','results']},indent=2))

if __name__=='__main__': main()
