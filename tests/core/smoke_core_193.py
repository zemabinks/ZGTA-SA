#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Shared traffic clock continuity and retained native gameplay regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['node','tests/server/smoke_traffic_clock.js'],
    ['python3','tests/core/smoke_core_192.py',*sys.argv[1:]],
]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core193 shared traffic clock and selected core chain; rendered and original retail parity remain separate')
