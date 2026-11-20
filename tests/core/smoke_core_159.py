#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""NPC pose/task ownership and retained complete core source chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
for command in [['node','tests/server/smoke_population_routes.js'],
                ['python3','tests/network/smoke_native_ambient_animation.py'],
                ['python3','tests/core/smoke_core_158.py',*sys.argv[1:]]]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core159 selected source gates; rendered NPC/browser/retail parity and complete AI remain separate')
