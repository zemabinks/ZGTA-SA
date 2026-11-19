#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core122 source gates; real physics is optional and game assets stay separate."""
from pathlib import Path
import argparse,os,subprocess

root=Path(__file__).resolve().parent
p=argparse.ArgumentParser(description=__doc__,add_help=False)
p.add_argument('--with-physics',action='store_true')
args,prior=p.parse_known_args()
os.setpriority(os.PRIO_PROCESS,0,15)
commands=[['python3','smoke_core_121.py',*prior],
          ['python3','smoke_native_vehicle_presentation.py'],
          ['python3','smoke_native_remote_bike_owner.py']]
if args.with_physics:commands.append(['python3','smoke_native_parked_phase.py'])
for command in commands:subprocess.run(command,cwd=root,check=True)
print('PASS Core122 selected source gates; rendered/device/retail acceptance remains separate')
