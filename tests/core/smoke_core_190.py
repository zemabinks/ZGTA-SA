#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Optional NPC reference-carrier compatibility and retained gameplay checks."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['python3', 'tests/network/smoke_native_ambient_reference_carrier.py'],
    ['python3', 'tests/core/smoke_core_189.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core190 authored optional-carrier contract and selected source chain; no new archived or retail comparison')
