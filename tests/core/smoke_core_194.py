#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Visible HUD icon recovery and retained native gameplay regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/ui/smoke_native_hud_icon_polling.py'],
    ['python3','tests/core/smoke_core_193.py',*sys.argv[1:]],
]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core194 visible HUD icon recovery and selected core chain; rendered recovery and original retail parity remain separate')
