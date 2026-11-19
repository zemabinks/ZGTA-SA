#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Portable Core117 source gates; SDK, original assets and live play are separate."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,json,subprocess,tempfile,time
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--with-transport',action='store_true',help='Include the existing optional lifecycle gate; requires a prebuilt host transport.')
args=parser.parse_args()
base=root/'local-only/research';base.mkdir(parents=True,exist_ok=True)
out=Path(tempfile.mkdtemp(prefix='core117-',dir=base))
commands=[['python3','tests/core/smoke_core_116.py']+(['--with-transport']if args.with_transport else[]),
 ['python3','tests/ui/smoke_native_controller_navigation.py'],['python3','tests/audio/smoke_native_radio_metadata.py'],
 ['python3','tests/audio/smoke_native_reload_audio.py'],['python3','tests/hosting/smoke_native_projectile_clock.py']]
results=[]
for command in commands:
 print('Running '+command[1],flush=True);started=time.monotonic();p=subprocess.run(command,cwd=root)
 results.append({'command':command,'exitCode':p.returncode,'seconds':time.monotonic()-started})
 (out/'results.json').write_text(json.dumps(results,indent=2)+'\n');p.check_returncode()
print('PASS Core117 portable native source gates; SDK/rendered/retail acceptance separate',flush=True)
