#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Stock source lifetime owners plus the retained selected core chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:]
subprocess.run(['python3','tests/resources/smoke_native_stock_source.py'],cwd=ROOT,check=True)
if '--with-stock-runtime' in args:
    subprocess.run(['python3','tests/network/test_samp_stock_runtime.py','--source-transitions'],cwd=ROOT,check=True)
    args=[a for a in args if a!='--with-stock-runtime']
subprocess.run(['python3','tests/core/smoke_core_148.py',*args],cwd=ROOT,check=True)
print('PASS Core149 selected source gates; stock HTTP/Metal/Rapier runtime is opt-in; installed, hardware and retail acceptance remain separate')
