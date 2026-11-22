#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Admitted NPC hit metadata and the retained current core regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['python3', 'tests/combat/smoke_native_population_hit_piece.py'],
    ['python3', 'tests/core/smoke_core_187.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core188 admitted NPC body-piece metadata and selected source chain; rendered reactions, full AI and retail accuracy remain separate')
