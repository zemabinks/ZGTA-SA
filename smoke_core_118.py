#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core118 source regressions; original assets and SDK/play tests are separate."""
from pathlib import Path
import argparse,json,subprocess,tempfile,time

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--with-transport',action='store_true',help='Include the existing prebuilt-host transport lifecycle gate.')
parser.add_argument('--with-owner-assets',action='store_true',help='Also run actual movement/audio and camera gates; requires the local animation archive, metadata and native physics library.')
parser.add_argument('--with-txd',action='store_true',help='Also run generated CPU texture-decoder cases; requires Swift and an already installed Pillow.')
args=parser.parse_args()
base=root/'local-only/research';base.mkdir(parents=True,exist_ok=True)
out=Path(tempfile.mkdtemp(prefix='core118-',dir=base))
commands=[['python3','smoke_core_117.py']+(['--with-transport']if args.with_transport else[]),
          ['python3','smoke_native_aim_ownership.py']]
if args.with_owner_assets:
    commands.extend([['python3','smoke_native_swim_reload_audio.py'],
                     ['python3','smoke_native_task_handoffs.py'],
                     ['python3','smoke_native_camera_motion.py']])
if args.with_txd:
    commands.append(['python3','test_native_renderware_txd.py','--no-corpus'])
results=[]
for command in commands:
    print('Running '+command[1],flush=True)
    started=time.monotonic();result=subprocess.run(command,cwd=root)
    results.append({'command':command,'exitCode':result.returncode,'seconds':time.monotonic()-started})
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    result.check_returncode()
print('PASS Core118 selected source gates; SDK, rendered, hardware and retail acceptance remain separate',flush=True)
