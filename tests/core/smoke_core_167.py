#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compact traffic lamp inputs, typed audio and retained core regressions."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/network/smoke_native_traffic_signals.py'],
    ['python3','tests/audio/smoke_native_traffic_audio.py'],
    ['python3','tests/core/smoke_core_166.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core167 selected source gates; projected lamps, siren sprites, full traffic resources/AI, audio playback and retail acceptance remain separate')
