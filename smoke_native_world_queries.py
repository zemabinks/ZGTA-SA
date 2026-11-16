#!/usr/bin/env python3
"""Actual native collision, extracted Renderer query and fixed prediction gate."""
from pathlib import Path
import platform,subprocess,tempfile
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='zgta-world-queries-') as temporary:
    work=Path(temporary)
    renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    fixture=(ROOT/'smoke_native_world_queries.swift').read_text().replace('// RENDERER_QUERY',function(renderer,'private func worldRay(')).replace('// RENDERER_SCENE_OWNERSHIP',function(renderer,'private var isInterior:'))
    (work/'main.swift').write_text(fixture)
    names=['SwiftRapierWorld','NativeCharacterController','NativeCharacterMotor','NativeRapierCharacterQueries','NativeWorldRay','NativeWeaponEffects','NativeGameCamera','ServerAddress']
    subprocess.run(['xcrun','swiftc','-parse-as-library','-Onone','-module-cache-path','/private/tmp/zgtasa-world-query-modules',
        '-I',str(ROOT/'native-physics/include'),*[str(ROOT/'ios/App'/(n+'.swift')) for n in names],str(work/'main.swift'),
        '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
        '-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],check=True)
    subprocess.run([str(work/'verify'),str(ROOT/'local-only/site/game/native/camera.json')],check=True)
