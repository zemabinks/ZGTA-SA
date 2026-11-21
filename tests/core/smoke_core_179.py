#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Local foot presentation, bounded diagnostics and retained gameplay."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['python3', 'tests/movement/smoke_native_foot_presentation.py'],
    ['python3', 'tests/hosting/smoke_public_source.py'],
    ['python3', 'tests/core/smoke_core_178.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core179 display/diagnostic/source regressions and retained core chain; actual App, hardware and retail remain separate')
