#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core202 precise remote armour reactions and authoritative NPC fire occurrences."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run([sys.executable,'tests/network/smoke_native_remote_armour.py'],cwd=ROOT,check=True)
subprocess.run([sys.executable,'tests/core/smoke_core_201.py',*sys.argv[1:]],cwd=ROOT,check=True)
