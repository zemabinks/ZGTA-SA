#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Immediate compact shots, ordinary effects/audio and retained core gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:]
for command in [
    ['python3','tests/network/smoke_native_traffic_shots.py'],
    ['python3','tests/rendering/smoke_native_shot_tracers.py',*(['--require-gpu']if '--require-gpu'in args else[])],
    ['python3','tests/audio/smoke_native_shot_attack.py',*([]if '--with-audio'in args else['--compile-only'])],
    ['python3','tests/core/smoke_core_168.py',*args],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core169 selected source gates; original seated gun posture/holders, human-shot subscription, procedural fallback FX, audio output, app and retail acceptance remain separate')
