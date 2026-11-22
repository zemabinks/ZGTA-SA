#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Static zone configuration and the retained current core regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['python3', 'tests/resources/test_zone_initialization.py'],
    ['python3', 'tests/resources/test_population_tables.py'],
    ['python3', 'tests/core/smoke_core_185.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core186 static zone configuration and selected source chain; no script execution or original density/AI acceptance')
