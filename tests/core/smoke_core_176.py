#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Foreground input ownership, reload feedback and retained native gameplay."""
from pathlib import Path
import os, subprocess, sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
commands=[['python3','tests/input/smoke_native_foreground_input.py']]
# The full transport chain already executes this real HTTP/WS boundary.
if '--with-transport'not in sys.argv[1:]:
    commands.append(['python3','tests/network/smoke_native_inventory_wire.py'])
commands.append(['python3','tests/core/smoke_core_175.py',*sys.argv[1:]])
for command in commands:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core176 selected input/feedback/source checks; actual App, contact, hardware and retail acceptance remain separate')
