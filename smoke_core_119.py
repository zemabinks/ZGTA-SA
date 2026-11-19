#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core119 authored source gates; SDK, original assets and live play are separate."""
from pathlib import Path
import argparse,json,os,subprocess,tempfile,time

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--with-transport',action='store_true')
parser.add_argument('--with-owner-assets',action='store_true')
parser.add_argument('--with-txd',action='store_true')
parser.add_argument('--with-producer',action='store_true',help='Include authored producer cases; requires installed Pillow.')
parser.add_argument('--with-metal',action='store_true',help='Include actual offscreen host GPU; requires the Metal compiler and a usable GPU.')
args=parser.parse_args()
# Positive nice values reduce test load. The bounded HTTP gate verifies this
# exact outer-process priority; its child compiler inherits it.
if os.getpriority(os.PRIO_PROCESS,0)!=15: os.setpriority(os.PRIO_PROCESS,0,15)
base=root/'local-only/research';base.mkdir(parents=True,exist_ok=True)
out=Path(tempfile.mkdtemp(prefix='core119-',dir=base))
prior=['python3','smoke_core_118.py']
for name in ['with_transport','with_owner_assets','with_txd']:
    if getattr(args,name): prior.append('--'+name.replace('_','-'))
commands=[prior]+[['python3',name] for name in [
    'smoke_native_ped_atlas_layout.py','smoke_native_ped_atlas_loader.py',
    'smoke_native_ped_atlas_dispatch.py','test_native_bounded_resources.py',
    'test_native_resources.py']]
if args.with_producer: commands.append(['python3','test_native_ped_atlas.py'])
if args.with_metal: commands.append(['python3','smoke_native_ped_atlas_gpu.py'])
results=[]
for command in commands:
    print('Running '+command[1],flush=True)
    started=time.monotonic();result=subprocess.run(command,cwd=root)
    results.append({'command':command,'exitCode':result.returncode,'seconds':time.monotonic()-started})
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    result.check_returncode()
print('PASS Core119 selected source gates; SDK, rendered, hardware and retail acceptance remain separate',flush=True)
