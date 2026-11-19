#!/usr/bin/env python3
"""Actual native hit sequencing and server front-block authority."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from tests.combat.smoke_native_hit_backend import main
if __name__ == '__main__':
    main('parry')
