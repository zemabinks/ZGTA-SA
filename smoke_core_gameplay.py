#!/usr/bin/env python3
"""Run the core regression gate; retail-runtime parity is a separate gate.

Owner-provided assets and the native physics toolchain must be prepared first.
Results/logs stay under ignored local-only; no original fixtures are published.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'local-only/native-physics/tests/core-gameplay-gate'


def hashes():
    paths = [*sorted(p for p in ROOT.iterdir() if p.is_file() and p.suffix in {'.py','.js','.swift','.sh','.cpp','.hpp','.pwn'}),
             *sorted(p for p in (ROOT / 'ios/App').rglob('*') if p.is_file()),
             *sorted((ROOT / 'native-physics/src').rglob('*.rs')),
             *sorted(p for p in (ROOT / 'native-physics/tests').rglob('*') if p.is_file()),
             *sorted((ROOT / 'native-physics').glob('*.sh')),
             *sorted(p for p in (ROOT / 'native-physics/include').iterdir() if p.is_file()),
             ROOT / 'native-physics/Cargo.toml', ROOT / 'native-physics/Cargo.lock',
             ROOT / 'native-physics/source_stamp.py']
    # Network/codec sources participate in the same frozen-source boundary.
    # Walk only source files, excluding downloaded build products and caches.
    for directory in ['native-samp','native-menu-codec','tests']:
        base=ROOT/directory
        if base.exists():
            paths += sorted(p for p in base.rglob('*') if p.is_file()
                            and not any(part in {'build','target','vendor','node_modules','.git','local-only','__pycache__'} for part in p.relative_to(base).parts)
                            and (p.suffix in {'.go','.mod','.sum','.c','.cpp','.h','.hpp','.rs','.toml','.lock','.sh','.py','.js','.json','.swift','.pwn','.metal'} or p.name in {'go.mod','go.sum'}))
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def main():
    if sys.platform != 'darwin':
        raise SystemExit('This gate requires the macOS Swift/Metal development host. Server tests also run independently with Node.')
    required = [ROOT / 'local-only/selfhost/weapon-catalog.json',
                ROOT / 'local-only/selfhost/client-catalog.json',
                ROOT / 'local-only/site/game/native/foot-animation.json',
                ROOT / 'local-only/site/game/native/models/animations.clips.bin',
                ROOT / 'local-only/original-world-assets/game/native/stock-models.json',
                ROOT / 'local-only/research/samp-ped-height/mesh-observations.json']
    missing = [str(p.relative_to(ROOT)) for p in required if not p.is_file()]
    if missing:
        raise SystemExit('Prepare the owner-provided local assets/catalogs before this gate. Missing: ' + ', '.join(missing))
    OUT.mkdir(parents=True, exist_ok=True)
    before = hashes()
    cases = [(p.removesuffix('.py'), ['python3', p]) for p in [
        'smoke_native_fixed_velocity.py', 'smoke_native_task_handoffs.py', 'smoke_native_fall_damage.py', 'smoke_native_health.py',
        'smoke_native_camera_motion.py', 'smoke_native_world_reset.py', 'smoke_vehicle_air_handoff.py', 'smoke_train_layout.py',
        'smoke_native_combat_transitions.py', 'smoke_native_combat_animation.py', 'smoke_native_fire_arrival.py', 'smoke_native_reload_dispatch.py', 'smoke_native_respawn_dispatch.py', 'smoke_native_connection_recovery.py', 'smoke_native_recovery.py', 'smoke_native_connection_owners.py', 'smoke_native_gameplay_idle.py',
        'smoke_native_weapon_roles.py', 'smoke_native_combat_eligibility.py',
        'smoke_native_combat_interruptions.py', 'smoke_native_combat_dispatch.py',
        'smoke_native_effort_recovery.py', 'smoke_native_coupling_wire.py', 'smoke_native_coupling_controls.py',
        'smoke_native_coupling_backend.py',
        'smoke_vehicle_coupling.py', 'smoke_vehicle_working_rigs.py',
        'smoke_native_vehicle_support.py', 'smoke_native_vehicle_treads.py',
        'smoke_native_moving_support.py', 'smoke_native_support_runtime.py', 'smoke_native_support_backend.py',
        'smoke_native_local_hit.py', 'smoke_native_hit_runtime.py', 'smoke_native_hit_backend.py', 'smoke_native_parry_backend.py', 'smoke_native_wreck_backend.py', 'smoke_native_water_backend.py', 'smoke_native_impact_health.py', 'smoke_native_impact_backend.py', 'smoke_native_vehicle_water_exit.py', 'smoke_native_bike_ejection.py', 'smoke_native_bike_exit.py', 'smoke_native_exit_placement.py', 'smoke_native_exit_runtime.py', 'smoke_native_exit_heading_backend.py',
        'smoke_native_settings.py', 'smoke_native_menu_layout.py', 'smoke_native_menu_profile.py',
        'smoke_native_menu_keys.py', 'smoke_native_audio_settings.py', 'smoke_native_menu_sound.py',
        'smoke_native_heading_transitions.py', 'smoke_native_task_transitions.py',
        'smoke_native_shot_delivery.py', 'smoke_native_stream_shots.py', 'smoke_native_bindings.py',
        'smoke_native_melee.py', 'smoke_native_melee_delivery.py', 'smoke_native_weapon_attachment.py',
        'smoke_native_remote_melee.py',
        'smoke_native_shot_targeting.py', 'smoke_native_shot_occlusion.py',
        'smoke_native_world_queries.py', 'smoke_native_character_transitions.py', 'smoke_native_weapon_muzzle.py',
        'smoke_native_climb.py', 'smoke_native_climb_runtime.py',
        'smoke_native_ammo_reconciliation.py', 'smoke_native_inventory_wire.py',
        'smoke_native_camera_visibility.py',
        'smoke_native_controls.py', 'smoke_native_horn.py', 'smoke_native_wire.py',
        'smoke_native_foot_locomotion.py', 'smoke_native_foot_animation.py',
        'smoke_native_gun_animation.py', 'smoke_native_swim_animation.py',
        'smoke_native_swim_sprint.py', 'smoke_native_world_water.py', 'smoke_native_personal_flight.py',
        'smoke_native_flight_animation.py', 'smoke_native_camera.py', 'smoke_native_foot_look_behind.py',
        'smoke_native_remote_foot.py', 'smoke_native_rider_playback.py', 'smoke_native_rider_cancellation.py',
        'smoke_native_weapon_effects.py', 'smoke_bicycle_input.py',
        'smoke_original_world_protocol.py', 'smoke_original_world_arsenal.py',
        'smoke_original_world_weapons.py', 'smoke_original_world_staff.py', 'smoke_original_world_wire.py',
        'smoke_native_original_controller.py', 'smoke_native_original_commands.py', 'smoke_native_original_renderer.py',
        'smoke_native_original_vitals.py', 'smoke_native_original_gameplay.py',
        'smoke_native_samp_protocol.py', 'smoke_samp_server_ui.py', 'smoke_samp_artwork.py',
        'smoke_samp_input.py', 'smoke_samp_lifecycle.py', 'smoke_samp_gameplay.py', 'smoke_samp_objects.py',
        'smoke_native_renderware_dff.py', 'smoke_native_renderware_skeleton.py',
        'smoke_native_renderware_collision.py', 'smoke_native_renderware_collision_world.py',
        'test_native_renderware_txd.py', 'test_native_renderware_model.py', 'smoke_native_renderware_ped.py',
        'test_samp_artwork_session.py', 'test_samp_object_materials.py', 'test_samp_game_camera.py', 'test_samp_stock_models.py',
        'smoke_original_auth.py', 'smoke_samp_vehicle_coordinates.py', 'smoke_samp_combat_sync.py',
        'test_native_skin_namespace.py', 'test_native_skin_network.py', 'test_native_vehicle_paint.py',
        'test_stock_asset_access.py', 'smoke_native_stock_collision.py', 'test_samp_stock_runtime.py',
        'test_stock_img_assets.py',
        'smoke_samp_controls.py', 'smoke_samp_vitals.py',
    ]]
    cases += [(p.removesuffix('.js'), ['node', p]) for p in [
        'smoke_browser_armour_sync.js', 'smoke_weapon_inventory.js', 'smoke_weapon_cadence.js', 'smoke_weapon_streams.js', 'smoke_weapon_transport.js', 'smoke_native_server.js', 'smoke_inventory_ack.js', 'smoke_jetpack_drop.js', 'smoke_vehicle_departure.js', 'smoke_health_ack.js',
        'smoke_native_melee_server.js', 'smoke_native_melee_assets.js', 'smoke_native_parry.js',
        'smoke_vehicle_coupling_server.js', 'smoke_native_working_stage.js', 'smoke_native_working_assets.js',
    ]]
    cases.append(('samp_ped_coordinate_calibration',['python3','smoke_samp_coordinates.py',str(ROOT/'local-only/research/samp-ped-height/mesh-observations.json')]))
    cases.append(('core_physics_transitions', ['zsh', 'smoke_core_physics_transitions.sh']))
    cases.append(('native_sphere', ['zsh', 'native-physics/test_sphere.sh']))
    cases.append(('native_joints', ['zsh', 'native-physics/test_joints.sh']))
    cases.append(('vehicle_lifecycle',['zsh','smoke_vehicle_lifecycle.sh']))

    def run(case):
        name, command = case
        start = time.monotonic()
        with (OUT / (name + '.log')).open('w') as log:
            try:
                result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=600)
                code = result.returncode
            except subprocess.TimeoutExpired:
                log.write('\nFAIL: timed out after600s\n')
                code = 124
        row = {'name': name, 'command': command, 'returncode': code, 'seconds': round(time.monotonic()-start, 2)}
        print(('PASS ' if code == 0 else 'FAIL ') + name, flush=True)
        return row

    # Large native compilers and actual GPU readbacks share this development
    # host. Keep concurrency explicit so a bounded gate also runs on16GB Macs.
    workers=int(os.environ.get('ZGTA_CORE_WORKERS','2'))
    if not 1<=workers<=4:
        raise SystemExit('ZGTA_CORE_WORKERS must be1..4')
    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(run, cases))

    # The archived browser replays the exact packets produced by the server
    # fixture. Keep that producer/consumer pair sequential and outside the pool.
    for script in ['smoke_selfhost_vehicle_presence.js', 'smoke_selfhost_vehicle_presence_browser.js']:
        results.append(run((script.removesuffix('.js'), ['node', script])))

    # The raw and catalog-aware controls fixtures deliberately use the same
    # matching UDP port. Run this second profile after the pool has released it.
    results.append(run(('samp_vehicle_coordinate_udp',['python3','smoke_samp_controls.py','--vehicle-metadata',str(ROOT/'local-only/site/game/native/vehicles.physics.json')])))

    # Compile integration boundaries against the actual helpers, not stand-ins.
    for name in ['weapon_state']:
        source = ROOT / f'smoke_native_{name}.swift'
        with tempfile.TemporaryDirectory(prefix='zgta-core-' + name + '-') as temporary:
            binary = str(Path(temporary) / 'verify')
            dependencies = ['NativeInventoryPrediction', 'NativeOriginalWorldArsenal', 'NativeWeaponState']
            compile_command = ['xcrun', 'swiftc', '-O', '-module-cache-path', str(OUT / 'modules')]
            compile_command += [str(ROOT / 'ios/App' / (n+'.swift')) for n in dependencies]
            compile_command += [str(source), '-o', binary]
            compile_result = run(('compile_' + name, compile_command))
            results.append(compile_result)
            if compile_result['returncode'] == 0:
                results.append(run((name, [binary])))

    unchanged = before == hashes()
    report = {'at': datetime.now(timezone.utc).isoformat(), 'sourceUnchanged': unchanged,
              'evidence': 'native/browser regression and isolated network tests; not original retail-runtime parity',
              'hashes': before, 'tests': results}
    (OUT / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    failed = [r['name'] for r in results if r['returncode'] != 0]
    if not unchanged:
        failed.append('source changed during gate; rerun against a frozen snapshot')
    print(f'{sum(r["returncode"] == 0 for r in results)}/{len(results)} gates passed; sources unchanged={unchanged}')
    if failed:
        print('Failures: ' + ', '.join(failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
