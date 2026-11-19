#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core130 source regressions; runtime and original-game parity stay separate."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,os,subprocess

root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__,add_help=False)
parser.add_argument('--with-physics',action='store_true')
parser.add_argument('--with-audio',action='store_true')
args,prior=parser.parse_known_args()
os.setpriority(os.PRIO_PROCESS,0,15)
commands=[['python3','tests/core/smoke_core_127.py',*(['--with-physics'] if args.with_physics else []),*prior],
          ['python3','build_installer_bridge.py','--platform','host'],
          ['python3','tests/resources/smoke_native_raw_directory_case.py'],
          ['python3','tests/resources/smoke_native_raw_resources.py'],
          ['python3','tests/resources/smoke_native_raw_leases.py','--installer-archive','local-only/native-installer/host/libzgtasa_installer.a']]
if args.with_physics:commands.append(['python3','tests/vehicles/smoke_native_owned_wheel_phase.py'])
if args.with_audio:commands.append(['python3','tests/audio/smoke_native_local_radio.py'])
for command in commands:subprocess.run(command,cwd=root,check=True)
print('PASS Core130 selected source checks; optional physics/audio need their source-stamped host libraries. Live playback, device and retail parity remain separate.')
