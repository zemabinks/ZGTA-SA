#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Missing-water input-owner regression plus existing core source checks."""
from pathlib import Path
import os, subprocess, sys

root=Path(__file__).resolve().parent
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','smoke_native_swim_retirement.py'],cwd=root,check=True)
subprocess.run(['python3','smoke_core_134.py',*sys.argv[1:]],cwd=root,check=True)
print('PASS Core136 selected source gates; original timing, rendered and physical-device acceptance remain separate')
