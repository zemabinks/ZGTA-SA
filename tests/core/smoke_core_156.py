#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Current-source/latest metadata admission and existing gameplay gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:];physics=['--with-physics']if '--with-physics'in args else[]
subprocess.run(['python3','tests/resources/smoke_native_metadata_source.py',*physics],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_155.py',*args],cwd=ROOT,check=True)
print('PASS Core156 selected source gates; normal app, hardware and original-retail acceptance remain separate')
