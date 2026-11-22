#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Observable NPC lifetimes and the retained current core regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['node', 'tests/server/smoke_population_observation.js'],
    ['node', 'tests/server/smoke_population_observation_backend.js'],
    ['python3', 'tests/core/smoke_core_186.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core187 observable population lifetime and selected source chain; original density/AI and rendered/retail acceptance remain separate')
