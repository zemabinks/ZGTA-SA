#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authoritative NPC event intervals and retained native gameplay regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['node', 'tests/server/smoke_population_event_clock.js'],
    ['node', 'tests/server/smoke_population_event_backend.js'],
    ['python3', 'tests/core/smoke_core_190.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core191 shared NPC event clocks and selected core chain; original movement parameters, rendered and retail parity remain separate')
