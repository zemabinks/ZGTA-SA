#!/usr/bin/env python3
"""Verify shot visibility against actual native collision, without UI control."""
from pathlib import Path
import platform, subprocess, tempfile
ROOT=Path(__file__).resolve().parent

def main():
    with tempfile.TemporaryDirectory(prefix='zgta-shot-occlusion-') as temporary:
        binary=Path(temporary)/'verify'
        subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path','/private/tmp/zgtasa-shot-modules',
            '-I',str(ROOT/'native-physics/include'),str(ROOT/'ios/App/SwiftRapierWorld.swift'),
            str(ROOT/'ios/App/NativeShotOcclusion.swift'),str(ROOT/'smoke_native_shot_occlusion.swift'),
            '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
            '-framework','Security','-framework','CoreFoundation','-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
if __name__=='__main__':main()
