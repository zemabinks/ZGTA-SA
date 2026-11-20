#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""NPC original-activity transitions and retained complete core source chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
for command in [['python3','tests/resources/test_native_population_profiles.py'],
                ['python3','tests/network/smoke_native_ambient_activity.py'],
                ['python3','tests/core/smoke_core_159.py',*sys.argv[1:]]]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core160 selected source gates; complete NPC events/AI, rendered activities and original retail parity remain separate')
