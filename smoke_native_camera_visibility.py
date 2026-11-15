#!/usr/bin/env python3
"""Exercise native own-camera clipping safety without operating Simulator."""
from pathlib import Path
import shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parent

def main():
    output=ROOT/'local-only/native-physics/tests/camera-visibility';output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='run-',dir=output) as temporary:
        work=Path(temporary)
        for name,source in [('NativeCameraVisibility.swift',ROOT/'ios/App/NativeCameraVisibility.swift'),('main.swift',ROOT/'smoke_native_camera_visibility.swift')]:
            shutil.copyfile(source,work/name)
        subprocess.run(['xcrun','swiftc','-O','-parse-as-library','-module-cache-path',str(output/'modules'),str(work/'NativeCameraVisibility.swift'),str(work/'main.swift'),'-o',str(work/'verify')],check=True)
        subprocess.run([str(work/'verify')],check=True)
if __name__=='__main__':main()
