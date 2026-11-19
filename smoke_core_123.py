#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core123 source gates; optional actual Metal output needs a native device."""
from pathlib import Path
import argparse,os,subprocess

root=Path(__file__).resolve().parent
p=argparse.ArgumentParser(description=__doc__,add_help=False)
p.add_argument('--with-model-metal',action='store_true')
args,prior=p.parse_known_args()
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','smoke_core_122.py',*prior],cwd=root,check=True)
subprocess.run(['python3','test_native_renderware_model.py',
                '--require-metal' if args.with_model_metal else '--cpu-only'],cwd=root,check=True)
print('PASS Core123 selected source gates; game-world/device/retail acceptance remains separate')
