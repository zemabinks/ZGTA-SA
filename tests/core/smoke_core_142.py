#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Original navigation/resource lifecycle checks plus the complete prior chain."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [['python3', 'tests/resources/smoke_native_original_navigation.py'],
                ['python3', 'tests/core/smoke_core_140.py', *sys.argv[1:]]]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core142 source gates; original AI and retail gameplay parity remain separate')
