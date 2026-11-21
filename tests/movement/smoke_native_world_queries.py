#!/usr/bin/env python3
"""Actual native collision, extracted Renderer query and fixed prediction gate."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import platform,subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='zgta-world-queries-') as temporary:
    work=Path(temporary)
    renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    fixture=(ROOT/'tests/movement/smoke_native_world_queries.swift').read_text().replace('// RENDERER_QUERY',function(renderer,'private func worldRay(')).replace('// RENDERER_SCENE_OWNERSHIP',function(renderer,'private var isInterior:'))
    (work/'main.swift').write_text(fixture)
    names=['SwiftRapierWorld','NativeCharacterController','NativeCharacterMotor','NativeRapierCharacterQueries','NativeWorldRay','NativeWeaponEffects','NativeGameCamera','ServerAddress']
    subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path','/private/tmp/zgtasa-world-query-modules',
        '-I',str(ROOT/'native-physics/include'),*[str(ROOT/'ios/App'/(n+'.swift')) for n in names],str(work/'main.swift'),
        '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
        '-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],check=True)
    subprocess.run([str(work/'verify'),str(ROOT/'local-only/site/game/native/camera.json')],check=True)
