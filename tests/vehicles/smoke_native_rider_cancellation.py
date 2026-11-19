#!/usr/bin/env python3
"""Replay interrupted entry/exit against actual public bA with original rigs."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import json
from pathlib import Path
import subprocess
import tests.vehicles.smoke_native_rider_playback as replay
import tools.assets.prepare_native_animations as archive
from tests.movement.smoke_native_foot_animation import SWIFT as FOOT_SWIFT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--playback-source', type=Path)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = root / 'local-only/research/core80-rider-cancellation'
    work.mkdir(parents=True, exist_ok=True)
    old = "const method=frame===480?'leave':null;if(method)original.leave(side,null,false);"
    new = "const method=frame===20||frame===500?'sit':frame===480?'leave':null;const heldDoor=method==='sit'&&original.door!==null;if(method==='sit')original.sit();else if(method)original.leave(side,null,false);"
    assert old in replay.JS
    js = replay.JS.replace(old, new).replace('method,state:original.state', 'method,cancelledDoor:heldDoor,state:original.state')
    js = js.replace('fs.writeFileSync(process.argv[3],JSON.stringify(rows));', "if(rows.filter(row=>row.cancelledDoor).length<2)throw Error('No actual held-door cancellations exercised');fs.writeFileSync(process.argv[3],JSON.stringify(rows));")
    swift = replay.SWIFT.replace('if row["method"] as? String=="leave"{playback.leave(side:side)}',
        'if row["method"] as? String=="leave"{playback.leave(side:side)}\n if row["method"] as? String=="sit"{playback.sit()}')
    swift = swift.replace('assert(actual.state.rawValue==', 'if row["cancelledDoor"] as? Bool==true{assert(actual.doorPart==nil,"Cancelled rider exported a stale door hold")}\n assert(actual.state.rawValue==')
    (work / 'reference.js').write_text(js)
    (work / 'order.json').write_text(json.dumps(archive.pedestrian_data(archive.GAME / 'bmori.dff')[5]))
    subprocess.run(['node', str(work / 'reference.js'), str(work / 'order.json'), str(work / 'reference.json')], cwd=root, check=True)
    names = ['NativeActorAnimation', 'NativeGunAnimation', 'NativeSwimAnimation', 'NativeFlightAnimation', 'NativeFootAnimation', 'NativeRiderAnimation', 'NativeBoardingAnimation']
    playback = args.playback_source or root / 'ios/App/NativeRiderPlayback.swift'
    text = (root / 'ios/App/NativeSkeletalActor.swift').read_text() + '\n'.join((root / 'ios/App' / (name + '.swift')).read_text() for name in names)
    text += playback.read_text() + FOOT_SWIFT[:FOOT_SWIFT.index('let root=')] + swift
    (work / 'verify.swift').write_text(text)
    subprocess.run(['xcrun', 'swiftc', '-Onone', '-whole-module-optimization', '-module-cache-path', str(root / 'local-only/native-physics/swift-module-cache'), str(work / 'verify.swift'), '-o', str(work / 'verify')], check=True)
    if not args.prepare_only:
        subprocess.run([str(work / 'verify'), str(root), str(work / 'reference.json')], check=True)


if __name__ == '__main__':
    main()
