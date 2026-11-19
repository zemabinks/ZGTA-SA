#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Browser compressed-radio HTTP coverage plus the existing native source gates."""
from pathlib import Path
import os, subprocess, sys

root = Path(__file__).resolve().parent
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in (['node', 'smoke_browser_radio.js'],
                ['node', 'smoke_browser_radio_http.js'],
                ['python3', 'smoke_core_131.py', *sys.argv[1:]]):
    subprocess.run(command, cwd=root, check=True)
print('PASS Core134 selected source gates; audible output, physical controls and retail parity remain separate')
