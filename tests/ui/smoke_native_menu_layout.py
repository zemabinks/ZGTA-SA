#!/usr/bin/env python3
"""Compile and exercise the actual native menu geometry without private artwork."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[2]
out=root/'local-only/native-physics/tests/menu-layout';out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='zgta-menu-layout-') as folder:
 binary=str(Path(folder)/'verify')
 subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),str(root/'ios/App/NativeMainMenuLayout.swift'),str(root/'tests/ui/smoke_native_menu_layout.swift'),'-o',binary],check=True,cwd=root)
 subprocess.run([binary],check=True,cwd=root)
