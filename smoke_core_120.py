#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core120 source regressions; original data, SDK and live play remain separate."""
from pathlib import Path
import argparse,json,os,subprocess,tempfile,time

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
for flag in ['transport','owner-assets','txd','producer','metal']:
    parser.add_argument('--with-'+flag,action='store_true')
args=parser.parse_args()
if os.getpriority(os.PRIO_PROCESS,0)!=15:os.setpriority(os.PRIO_PROCESS,0,15)
base=root/'local-only/research';base.mkdir(parents=True,exist_ok=True)
out=Path(tempfile.mkdtemp(prefix='core120-',dir=base))
prior=['python3','smoke_core_119.py']
for name in ['transport','owner_assets','txd','producer','metal']:
    if getattr(args,'with_'+name):prior.append('--with-'+name.replace('_','-'))
model=['python3','test_native_renderware_model.py']
if not args.with_metal:model.append('--cpu-only')
results=[]
for command in [prior,model]:
    print('Running '+command[1],flush=True);started=time.monotonic()
    result=subprocess.run(command,cwd=root)
    results.append({'command':command,'exitCode':result.returncode,'seconds':time.monotonic()-started})
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    result.check_returncode()
print('PASS Core120 selected source gates; SDK, original-asset, hardware and retail acceptance remain separate',flush=True)
