#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core127 browser task-policy HTTP gate and prior native/source checks."""
from pathlib import Path
import os,subprocess,sys

root=Path(__file__).resolve().parent
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['node','smoke_browser_task_policy_http.js'],cwd=root,check=True)
subprocess.run(['python3','smoke_core_126.py',*sys.argv[1:]],cwd=root,check=True)
print('PASS Core127 selected source checks; live scenes and retail parity remain separate')
