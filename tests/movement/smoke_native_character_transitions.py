#!/usr/bin/env python3
"""Compile a private immutable snapshot against the read-only native core."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib, json, os, pathlib, platform, shutil, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'local-only/native-physics/tests/character-transitions'
OUT.mkdir(parents=True, exist_ok=True)
arch = {'arm64':'arm64','x86_64':'x86_64'}[platform.machine()]
lib = pathlib.Path(os.environ.get('PHYSICS_HOST_LIB', ROOT / f'local-only/native-physics/macos-{arch}'))
source = pathlib.Path(os.environ.get('CHARACTER_SOURCE_ROOT', ROOT))
report = OUT / os.environ.get('CHARACTER_REPORT_NAME','report.json')
with tempfile.TemporaryDirectory(prefix='source-', dir=OUT) as directory:
    snapshot = pathlib.Path(directory)
    files = ['SwiftRapierWorld.swift','NativeCharacterMotor.swift',
             'NativeRapierCharacterQueries.swift','NativeCharacterController.swift']
    sources=[]
    for name in files:
        target=snapshot/name
        shutil.copy2(source/'ios/App'/name,target);sources.append(str(target))
    shutil.copy2(ROOT/'tests/movement/smoke_native_character_transitions.swift',snapshot/'main.swift')
    shutil.copytree(ROOT/'native-physics/include',snapshot/'include')
    binary=snapshot/'verify'
    subprocess.run(['xcrun','swiftc','-O','-target',f'{arch}-apple-macosx13.0',
        '-module-cache-path',str(OUT/'module-cache'),'-I',str(snapshot/'include'),
        *sources,str(snapshot/'main.swift'),'-L',str(lib),'-lzgtasa_native_physics',
        '-framework','Security','-framework','CoreFoundation','-o',str(binary)],check=True)
    result=subprocess.run([str(binary),str(report)])
    if report.exists():
        data=json.loads(report.read_text())
        data['sourceSHA256']={name:hashlib.sha256((snapshot/name).read_bytes()).hexdigest() for name in files}
        data['librarySHA256']=hashlib.sha256((lib/'libzgtasa_native_physics.a').read_bytes()).hexdigest()
        report.write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
    raise SystemExit(result.returncode)
