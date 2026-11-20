#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Separate NPC channel, original pavement graph, tasks and retained core gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
if '--with-physics'in sys.argv:
    subprocess.run(['python3','tests/network/smoke_native_ambient_bodies.py'],cwd=ROOT,check=True)
for script in ['tests/resources/test_pedestrian_paths.py','tests/resources/test_population_selection.py','tests/network/smoke_native_ambient_pedestrians.py']:
    subprocess.run(['python3',script],cwd=ROOT,check=True)
for script in ['smoke_population_paths','smoke_population_protocol','smoke_population_tasks','smoke_population_backend']:
    subprocess.run(['node','tests/server/'+script+'.js'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_157.py',*sys.argv[1:]],cwd=ROOT,check=True)
print('PASS Core158 selected source gates; full original NPC/traffic/police AI, app gameplay, browser, phone and retail acceptance remain separate')
