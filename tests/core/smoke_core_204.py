#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core204 current and presented living-target admission and corpse continuity."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
subprocess.run([sys.executable,'tests/core/smoke_core_203.py',*sys.argv[1:]],cwd=ROOT,check=True)
