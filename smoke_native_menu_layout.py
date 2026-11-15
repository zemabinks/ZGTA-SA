#!/usr/bin/env python3
"""Compile and exercise the actual native menu geometry without private artwork."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent
out=root/'local-only/native-physics/tests/menu-layout';out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='zgta-menu-layout-') as folder:
 binary=str(Path(folder)/'verify')
 subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),str(root/'ios/App/NativeMainMenuLayout.swift'),str(root/'smoke_native_menu_layout.swift'),'-o',binary],check=True,cwd=root)
 subprocess.run([binary],check=True,cwd=root)
