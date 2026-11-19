#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core130 source regressions; runtime and original-game parity stay separate."""
from pathlib import Path
import argparse,os,subprocess

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__,add_help=False)
parser.add_argument('--with-physics',action='store_true')
parser.add_argument('--with-audio',action='store_true')
args,prior=parser.parse_known_args()
os.setpriority(os.PRIO_PROCESS,0,15)
commands=[['python3','smoke_core_127.py',*(['--with-physics'] if args.with_physics else []),*prior],
          ['python3','build_installer_bridge.py','--platform','host'],
          ['python3','smoke_native_raw_directory_case.py'],
          ['python3','smoke_native_raw_resources.py'],
          ['python3','smoke_native_raw_leases.py','--installer-archive','local-only/native-installer/host/libzgtasa_installer.a']]
if args.with_physics:commands.append(['python3','smoke_native_owned_wheel_phase.py'])
if args.with_audio:commands.append(['python3','smoke_native_local_radio.py'])
for command in commands:subprocess.run(command,cwd=root,check=True)
print('PASS Core130 selected source checks; optional physics/audio need their source-stamped host libraries. Live playback, device and retail parity remain separate.')
