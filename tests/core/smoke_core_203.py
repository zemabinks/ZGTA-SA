#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core203 current passive metadata across server, presentation and combat."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['node','tests/server/smoke_passive_rows.js'],cwd=ROOT,check=True)
subprocess.run([sys.executable,'tests/network/smoke_native_passive.py'],cwd=ROOT,check=True)
subprocess.run([sys.executable,'tests/core/smoke_core_202.py',*sys.argv[1:]],cwd=ROOT,check=True)
