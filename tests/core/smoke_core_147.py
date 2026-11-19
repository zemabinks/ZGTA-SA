#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Indexed world solid/clear phases, shared surface ordering and previous core chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15);args=sys.argv[1:]
for command in [['python3','tests/rendering/smoke_native_world_draw_plan.py'],['python3','tests/rendering/smoke_native_world_surfaces.py',*(['--require-gpu']if '--require-gpu'in args else[])],['python3','tests/vehicles/smoke_native_vehicle_transparency.py'],['python3','tests/core/smoke_core_146.py',*args]]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core147 selected source gates; full scene/material coverage, installed/hardware and classic retail parity remain separate')
