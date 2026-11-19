#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core131 explicit archive-route fences plus the existing native core gates."""
from pathlib import Path
import os,subprocess,sys

root=Path(__file__).resolve().parent
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['node','smoke_browser_task_policy_http.js','--archive-alias'],cwd=root,check=True)
subprocess.run(['python3','smoke_core_130.py',*sys.argv[1:]],cwd=root,check=True)
print('PASS Core131 selected source gates; live scenes and original-game parity remain separate')
