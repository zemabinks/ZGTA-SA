#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Prepared NPC resource admission and the retained current core chain."""
from pathlib import Path
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/resources/test_population_models.py'],
    ['node','tests/server/smoke_population_loader.js'],
    ['python3','tests/core/smoke_core_184.py',*sys.argv[1:]],
]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core185 source-family admission and selected core chain; actual native pose, GPU, ambient AI and retail parity remain separate')
