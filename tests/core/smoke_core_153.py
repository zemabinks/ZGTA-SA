#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Scene-resource publication and the existing selected gameplay regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
args = sys.argv[1:]
subprocess.run(['python3', 'tests/ui/smoke_native_camera_source.py'], cwd=ROOT, check=True)
if '--with-physics' in args:
    subprocess.run(['python3', 'tests/resources/smoke_native_collision_source.py'], cwd=ROOT, check=True)
subprocess.run(['python3', 'tests/core/smoke_core_152.py', *args], cwd=ROOT, check=True)
print('PASS Core153 selected source gates; rendered source transitions, hardware and original-retail acceptance remain separate')
