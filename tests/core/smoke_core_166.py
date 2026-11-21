#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Traffic occupant selection, resource/scene ownership and retained gates."""
from pathlib import Path
import os,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/resources/test_traffic_occupants.py'],
    ['python3','tests/network/smoke_native_traffic_occupants.py'],
    ['python3','tests/network/smoke_native_traffic_occupant_loading.py'],
    ['python3','tests/network/smoke_native_traffic_occupant_scene.py'],
    ['python3','tests/core/smoke_core_165.py',*sys.argv[1:]],
]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core166 selected source gates; rendered occupants, gun/look poses, astride death, traffic combat/AI and retail acceptance remain separate')
