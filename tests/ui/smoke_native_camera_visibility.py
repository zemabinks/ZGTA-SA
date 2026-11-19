#!/usr/bin/env python3
"""Exercise native own-camera clipping safety without operating Simulator."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]

def main():
    output=ROOT/'local-only/native-physics/tests/camera-visibility';output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='run-',dir=output) as temporary:
        work=Path(temporary)
        for name,source in [('NativeCameraVisibility.swift',ROOT/'ios/App/NativeCameraVisibility.swift'),('main.swift',ROOT/'tests/ui/smoke_native_camera_visibility.swift')]:
            shutil.copyfile(source,work/name)
        subprocess.run(['xcrun','swiftc','-O','-parse-as-library','-module-cache-path',str(output/'modules'),str(work/'NativeCameraVisibility.swift'),str(work/'main.swift'),'-o',str(work/'verify')],check=True)
        subprocess.run([str(work/'verify')],check=True)
if __name__=='__main__':main()
