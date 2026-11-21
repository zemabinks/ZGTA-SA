#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Full-window scope geometry, complete diagnostic transport and retained gameplay."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['python3', 'tests/ui/smoke_native_scope_layout.py'],
    ['python3', 'tests/ui/smoke_native_diagnostic_chunks.py'],
    ['python3', '-m', 'unittest', 'tests.resources.test_native_weapon_icons'],
    ['python3', 'tests/core/smoke_core_176.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core178 scope/transport regressions and retained core chain; actual App pixels, contact, hardware and retail remain separate')
