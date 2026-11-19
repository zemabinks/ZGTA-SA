#!/usr/bin/env python3
"""Verify shot visibility against actual native collision, without UI control."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import platform, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]

def main():
    with tempfile.TemporaryDirectory(prefix='zgta-shot-occlusion-') as temporary:
        binary=Path(temporary)/'verify'
        subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path','/private/tmp/zgtasa-shot-modules',
            '-I',str(ROOT/'native-physics/include'),str(ROOT/'ios/App/SwiftRapierWorld.swift'),
            str(ROOT/'ios/App/NativeShotOcclusion.swift'),str(ROOT/'tests/combat/smoke_native_shot_occlusion.swift'),
            '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
            '-framework','Security','-framework','CoreFoundation','-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
if __name__=='__main__':main()
