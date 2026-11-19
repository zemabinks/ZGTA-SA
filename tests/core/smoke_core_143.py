#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""World/model materials, bounded native ped textures and the prior chain."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
arguments = sys.argv[1:]
require_gpu = '--require-gpu' in arguments
if require_gpu:
    arguments = [value for value in arguments if value != '--require-gpu']
subprocess.run(['python3', 'tests/rendering/smoke_native_world_materials.py',
                *(['--require-gpu'] if require_gpu else [])], cwd=ROOT, check=True)
subprocess.run(['python3', 'tests/resources/smoke_native_ped_texture_plan.py'], cwd=ROOT, check=True)
if require_gpu:
    subprocess.run(['python3', 'tests/resources/smoke_native_ped_atlas_gpu.py'], cwd=ROOT, check=True)
subprocess.run(['python3', 'tests/core/smoke_core_142.py', *arguments], cwd=ROOT, check=True)
print('PASS Core143 source gates; inspect the Metal report for GPU availability. Retail parity remains separate')
