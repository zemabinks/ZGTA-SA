#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Exercise the CPU DFF decoder using generated inputs and optional owner files.

All binary fixtures, owner-derived expected values, logs and executables remain
under local-only/research/runtime-dff. The archived game directory is read only.
No network, game installation or original website script is needed by this test.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'local-only' / 'research' / 'runtime-dff'
STAMP = 0x1803ffff


def pack(fmt, *values):
    return struct.pack('<' + fmt, *values)


def chunk(kind, payload=b'', stamp=STAMP):
    return pack('III', kind, len(payload), stamp) + payload


def synthetic(**change):
    """Original three-vertex fixture with two frames, two UVs and a two-bone rig."""
    def matrix(x, y, z):
        scale = change.get('frame_scale', 1.)
        return (scale, 0., 0., 0., 1., 0., 0., 0., 1., x, y, z)
    def floats(values):
        return pack('f' * len(values), *values)
    parents = change.get('parents', [1, -1])
    frames = pack('I', 2) + b''.join(floats(matrix(*translation)) + pack('iI', parents[i], i + 11)
                                    for i, translation in enumerate([(2., 0., 0.), (0., 3., 0.)]))
    node_ids = change.get('node_ids', [0, 1])
    node_indices = change.get('node_indices', [0, 1])
    hierarchy = pack('IIIII', 0x100, 0, 2, 0, 36) + b''.join(
        pack('III', node_ids[i], node_indices[i], i) for i in range(2))
    frame_extensions = [chunk(3, chunk(0x253f2fe, b'limb\0') +
                              chunk(0x11e, pack('III', 0x100, change.get('limb_id', 1), 0))),
                        chunk(3, chunk(0x253f2fe, b'root\0') + chunk(0x11e, hierarchy))]
    if change.get('missing_extension'):
        frame_extensions.pop()
    frame_struct = chunk(1, frames)
    if change.get('duplicate_struct'):
        frame_struct *= 2
    frame_list = chunk(14, frame_struct + b''.join(frame_extensions))
    flags, uv_count = 0xbe, 2  # normals, prelit, two texture coordinate sets.
    vertex_count = change.get('vertex_count', 3)
    data = pack('HBBIII', flags, change.get('uv_count', uv_count), change.get('native', 0),
                1, vertex_count, change.get('morph_count', 2))
    data += bytes([255, 0, 0, 255, 0, 255, 0, 200, 0, 0, 255, 100])
    data += floats([0, 0, 1, 0, 0, 1]) + floats([.25, .5, .75, .5, .25, 1])
    data += pack('HHHH', 1, change.get('vertex_index', 0), change.get('material_index', 1), 2)
    positions = [0., 0., 0., 1., 0., 0., 0., 0., 1.]
    positions[0] = change.get('position_x', positions[0])
    data += floats([0., 0., 0., change.get('radius', 2.)]) + pack('II', 1, 1)
    data += floats(positions) + floats([0., 1., 0.] * 3)
    data += floats([0., 0., 0., 2.]) + pack('II', 1, 0)
    data += floats([0., .5, 0., 1., .5, 0., 0., .5, 1.])
    texture = chunk(6, chunk(1, pack('I', 0x1106)) + chunk(2, b'custom_skin\0') +
                    chunk(2, b'skin_alpha\0') + chunk(3))
    material = chunk(7, chunk(1, pack('I4BII3f', 7, 20, 12, 13, 60, 0, 1, .75, .25, .5)) +
                     texture + chunk(3))
    material_list = chunk(8, chunk(1, pack('Iii', 2, -1, change.get('material_reference', 0))) + material)
    used = change.get('used_bones', [0, 1])
    skin = pack('4B', 2, len(used), change.get('max_weights', 2), 0) + bytes(used)
    skin += bytes([change.get('bone_index', 0), 1, 0, 0] * 3)
    weights = change.get('weights', [1., 0., 0., 0., .25, .75, 0., 0., 0., 1., 0., 0.])
    skin += floats(weights)
    for translation in [(0., -3., 0.), (-2., -3., 0.)]:
        padding = change.get('matrix_padding', 0.)
        skin += floats([change.get('inverse_x', 1.), 0., 0., padding,
                        0., 1., 0., padding, 0., 0., 1., padding, *translation, padding])
    skin += pack('III', *change.get('skin_tail', (0, 0, 0)))
    geometry = chunk(15, chunk(1, data) + material_list + chunk(3, chunk(0x116, skin)))
    geometry_list = chunk(26, chunk(1, pack('I', 1)) + geometry)
    atomic = chunk(20, chunk(1, pack('IIII', change.get('atomic_frame', 0),
                                   change.get('atomic_geometry', 0), 5, 0)) + chunk(3))
    return chunk(16, chunk(1, pack('III', change.get('atomic_count', 1), 0, 0)) +
                 frame_list + geometry_list + atomic + chunk(3))


def static_synthetic():
    """An independently generated untextured, unskinned object clump."""
    frame = pack('I12fiI', 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, -1, 0)
    frame_list = chunk(14, chunk(1, frame) + chunk(3))
    material = chunk(7, chunk(1, pack('I4BII3f', 0, 128, 129, 130, 255, 0, 0, 1, 1, 1)) + chunk(3))
    materials = chunk(8, chunk(1, pack('Ii', 1, -1)) + material)
    geometry = pack('HBBIII', 2, 0, 0, 1, 3, 1) + pack('4H', 1, 0, 0, 2)
    geometry += pack('4fII9f', 0, 0, 0, 2, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    geometries = chunk(26, chunk(1, pack('I', 1)) + chunk(15, chunk(1, geometry) + materials + chunk(3)))
    atomic = chunk(20, chunk(1, pack('4I', 0, 0, 5, 0)) + chunk(3))
    return chunk(16, chunk(1, pack('III', 1, 0, 0)) + frame_list + geometries + atomic + chunk(3))


def reference(path, full):
    """Compare against the independent Python exporters, extending raw fields.

    The exporter intentionally recolours vehicle materials and normalizes names;
    the runtime decoder must retain raw data, so those fields are read directly.
    """
    import prepare_native_models as models
    import prepare_native_animations as animation
    data = path.read_bytes()
    # Independent stream boundary validation: IMG files may retain less than
    # one final 2,048-byte sector of zeros after complete top-level chunks.
    cursor, top_kinds = 0, []
    while cursor < len(data):
        remainder = data[cursor:]
        if not any(remainder):
            if len(data) % 2048 or len(remainder) >= 2048:
                raise ValueError('invalid IMG sector padding')
            data = data[:cursor]
            break
        if len(remainder) < 12:
            raise ValueError('incomplete top-level chunk')
        kind, size, _ = struct.unpack_from('<III', data, cursor)
        if size > len(remainder) - 12:
            raise ValueError('top-level chunk exceeds stream')
        top_kinds.append(kind); cursor += 12 + size
    if top_kinds not in ([16], [16, 3]):
        raise ValueError('expected clump and optional top-level extension')
    parts = models.children(data, models.first(list(models.chunks(data, 0, len(data))), 16))
    frame_chunk = models.first(parts, 14)
    frames = models.frame_list(data, frame_chunk)
    assert all(math.isfinite(value) for values, _ in frames for value in values), 'non-finite frame matrix'
    geometry_chunks = [c for c in models.children(data, models.first(parts, 26)) if c[0] == 15]
    atomic_chunks = [c for c in parts if c[0] == 20]
    atomics = [list(struct.unpack_from('<4I', data, models.first(models.children(data, c), 1)[1]))
               for c in atomic_chunks]
    geometries = []
    for geometry_chunk in geometry_chunks:
        children = models.children(data, geometry_chunk)
        start = models.first(children, 1)[1]
        flags, uv_count, _, triangles, vertices, morphs = struct.unpack_from('<HBBIII', data, start)
        cursor = start + 16
        prelit = [list(data[cursor + i * 4:cursor + i * 4 + 4]) for i in range(vertices)] if flags & 8 else []
        cursor += vertices * 4 if flags & 8 else 0
        uv_count = uv_count or (2 if flags & 0x80 else 1 if flags & 4 else 0)
        uv = []
        for _ in range(uv_count):
            uv.append([list(struct.unpack_from('<2f', data, cursor + i * 8)) for i in range(vertices)])
            cursor += vertices * 8
        faces = []
        for _ in range(triangles):
            b, a, material, c = struct.unpack_from('<4H', data, cursor); cursor += 8
            faces.append([a, b, c, material])
        targets = []
        for _ in range(morphs):
            sphere = list(struct.unpack_from('<4f', data, cursor)); cursor += 16
            has_positions, has_normals = struct.unpack_from('<2I', data, cursor); cursor += 8
            target = {'sphere': sphere, 'positions': [], 'normals': []}
            for key, present in [('positions', has_positions), ('normals', has_normals)]:
                if present:
                    target[key] = [list(struct.unpack_from('<3f', data, cursor + i * 12)) for i in range(vertices)]
                    cursor += vertices * 12
            targets.append(target)
        # Cross-check the extended reader against established exporter functions.
        points, exported_faces, _, colors, exported_uv = models.geometry(data, geometry_chunk)
        assert points == [tuple(x) for x in targets[0]['positions']]
        assert exported_faces == [tuple(x) for x in faces]
        assert (list(colors) if colors is not None else []) == [v for color in prelit for v in color]
        if uv:
            assert exported_uv == [tuple(x) for x in uv[0]]
        material_parts = models.children(data, models.first(children, 8))
        info = models.first(material_parts, 1)
        count = struct.unpack_from('<I', data, info[1])[0]
        refs = struct.unpack_from('<' + 'i' * count, data, info[1] + 4)
        material_chunks = iter(c for c in material_parts if c[0] == 7)
        materials = []
        for ref in refs:
            if ref >= 0:
                materials.append(materials[ref]); continue
            material = models.children(data, next(material_chunks))
            info = models.first(material, 1)
            flags_m, r, g, b, a, _, textured, *surface = struct.unpack_from('<I4BII3f', data, info[1])
            entry = {'flags': flags_m, 'color': [r, g, b, a], 'surface': surface}
            if textured:
                texture = models.children(data, models.first(material, 6))
                entry['filter'] = struct.unpack_from('<I', data, models.first(texture, 1)[1])[0]
                strings = [c for c in texture if c[0] == 2]
                entry['texture'], entry['mask'] = [data[c[1]:c[2]].split(b'\0')[0].decode('latin1') for c in strings]
            materials.append(entry)
        entry = {'flags': flags, 'uv': uv, 'prelit': prelit, 'triangles': faces,
                 'morphs': targets, 'materials': materials}
        ext = models.first(children, 3)
        skin = models.first(models.children(data, ext), 0x116) if ext else None
        if skin:
            cursor = skin[1]
            bones, used, max_weights, _ = struct.unpack_from('<4B', data, cursor); cursor += 4
            palette = list(data[cursor:cursor + used]); cursor += used
            indices = [list(data[cursor + i * 4:cursor + i * 4 + 4]) for i in range(vertices)]
            cursor += vertices * 4
            weights = [list(struct.unpack_from('<4f', data, cursor + i * 16)) for i in range(vertices)]
            cursor += vertices * 16
            inverse = []
            for i in range(bones):
                raw = struct.unpack_from('<16f', data, cursor + i * 64)
                # Independent existing exporter converts RW padding to affine.
                row_major = animation.mat(raw, True)
                inverse.append([row_major[row * 4 + col] for col in range(4) for row in range(4)])
            entry['skin'] = {'bones': bones, 'used': palette, 'maxWeights': max_weights,
                             'indices': indices, 'weights': weights, 'inverse': inverse}
        geometries.append(entry)
    def finite_fields(value):
        if isinstance(value, dict):
            return all(finite_fields(item) for item in value.values())
        if isinstance(value, (tuple, list)):
            return all(finite_fields(item) for item in value)
        return not isinstance(value, float) or math.isfinite(value)
    if not finite_fields(geometries):
        raise ValueError('non-finite meaningful geometry/material/skin fields')
    result = {'version': 0x36003, 'frames': len(frames), 'geometries': len(geometries),
              'atomics': len(atomics), 'vertices': [len(g['morphs'][0]['positions']) for g in geometries],
              'triangles': [len(g['triangles']) for g in geometries],
              'skins': [g.get('skin', {}).get('bones', 0) for g in geometries]}
    if not full:
        return result
    frame_data = []
    frame_extensions = [c for c in models.children(data, frame_chunk) if c[0] == 3]
    globals_ = {}
    def world(index):
        if index not in globals_:
            local, parent = frames[index]
            globals_[index] = (animation.multiply(world(parent), animation.mat(local))
                               if parent >= 0 else animation.mat(local))
        return globals_[index]
    for i, (transform, parent) in enumerate(frames):
        plugins = models.children(data, frame_extensions[i])
        name = models.first(plugins, 0x253f2fe)
        name = data[name[1]:name[2]].split(b'\0')[0].decode('latin1') if name else ''
        flags = struct.unpack_from('<I', data, models.first(models.children(data, frame_chunk), 1)[1] + 4 + i * 56 + 52)[0]
        local, global_ = animation.mat(transform), world(i)
        row = {'name': name, 'parent': parent, 'flags': flags,
               'local': [local[r * 4 + c] for c in range(4) for r in range(4)],
               'world': [global_[r * 4 + c] for c in range(4) for r in range(4)]}
        hanim = models.first(plugins, 0x11e)
        if hanim:
            version, bone, count = struct.unpack_from('<III', data, hanim[1])
            flags, size = struct.unpack_from('<II', data, hanim[1] + 12) if count else (0, 0)
            nodes = [list(struct.unpack_from('<III', data, hanim[1] + 20 + j * 12)) for j in range(count)]
            row['hierarchy'] = {'version': version, 'id': bone, 'flags': flags, 'keyFrameSize': size, 'nodes': nodes}
        frame_data.append(row)
    result.update(frameData=frame_data, atomicData=atomics, geometryData=geometries)
    return result


def compare(actual, expected, where='model'):
    if isinstance(expected, dict):
        assert set(actual) == set(expected), (where, set(actual) ^ set(expected))
        for key in expected:
            compare(actual[key], expected[key], where + '.' + key)
    elif isinstance(expected, list):
        assert len(actual) == len(expected), (where, len(actual), len(expected))
        for i, value in enumerate(expected):
            compare(actual[i], value, where + f'[{i}]')
    elif isinstance(expected, float):
        assert math.isclose(actual, expected, rel_tol=2e-5, abs_tol=2e-5), (where, actual, expected)
    else:
        assert actual == expected, (where, actual, expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=ROOT / 'local-only/site/game')
    parser.add_argument('--no-archive', action='store_true', help='run only generated, distributable-input tests')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    fixtures = OUT / 'fixtures'; fixtures.mkdir(exist_ok=True)
    cases, expected = [], []
    def add(name, data, valid=False, full=False, limits=None):
        path = fixtures / (name + '.dff'); path.write_bytes(data)
        cases.append({'path': str(path), 'full': full, 'limits': limits})
        expected.append(reference(path, full) if valid else None)
    baseline = synthetic()
    add('generated-rig-two-uv-material-reference', baseline, valid=True, full=True)
    add('generated-rw-matrix-padding', synthetic(matrix_padding=float('nan')), valid=True, full=True)
    add('generated-untextured-static', static_synthetic(), valid=True, full=True)
    padded = baseline + bytes((-len(baseline)) % 2048)
    add('generated-img-sector-padding', padded, valid=True, full=True)
    extended = baseline + chunk(3)
    extended += bytes((-len(extended)) % 2048)
    add('generated-img-extension-sector-padding', extended, valid=True, full=True)
    add('img-nonzero-padding', padded[:-1] + b'\1')
    add('img-misaligned-padding', padded + b'\0')
    add('img-extra-whole-sector', padded + bytes(2048))
    add('img-whole-sector-padding', static_synthetic() + bytes(2048))
    malformed = {
        'native-platform': {'native': 1}, 'triangle-vertex': {'vertex_index': 3},
        'triangle-material': {'material_index': 2}, 'parent-cycle': {'parents': [1, 0]},
        'parent-self': {'parents': [0, -1]}, 'parent-range': {'parents': [99, -1]},
        'hanim-index': {'node_indices': [0, 2]}, 'hanim-duplicate': {'node_ids': [0, 0]},
        'hanim-missing-frame': {'limb_id': 12}, 'skin-index': {'bone_index': 2},
        'skin-duplicate-used': {'used_bones': [0, 0]}, 'skin-used-range': {'used_bones': [0, 2]},
        'skin-legacy': {'used_bones': []}, 'skin-influences': {'max_weights': 1},
        'skin-negative': {'weights': [-.1, 1.1, 0., 0.] * 3},
        'skin-zero-sum': {'weights': [0.] * 12}, 'skin-nan': {'weights': [float('nan')] + [0.] * 11},
        'skin-inf': {'weights': [float('inf')] + [0.] * 11}, 'skin-split': {'skin_tail': (0, 1, 0)},
        'skin-matrix-nan': {'inverse_x': float('nan')},
        'skin-matrix-inf': {'inverse_x': float('inf')},
        'world-matrix-overflow': {'frame_scale': 1e30},
        'position-nan': {'position_x': float('nan')}, 'position-inf': {'position_x': float('inf')},
        'negative-radius': {'radius': -1.}, 'no-morphs': {'morph_count': 0},
        'vertex-count-bomb': {'vertex_count': 0xffffffff}, 'uv-count-bomb': {'uv_count': 255},
        'material-forward-reference': {'material_reference': 1},
        'material-negative-reference': {'material_reference': -2},
        'atomic-frame': {'atomic_frame': 2}, 'atomic-geometry': {'atomic_geometry': 1},
        'atomic-count': {'atomic_count': 2}, 'frame-extension-count': {'missing_extension': True},
        'duplicate-struct': {'duplicate_struct': True},
    }
    for name, changes in malformed.items():
        add(name, synthetic(**changes))
    add('big-endian', b'\0\0\0\x10' + baseline[4:])
    add('oversized-root', baseline[:4] + pack('I', 0xffffffff) + baseline[8:])
    add('trailing-byte', baseline + b'\0')
    add('unrecognized-version', baseline[:8] + pack('I', 0) + baseline[12:])
    for length in range(len(baseline)):
        add(f'truncated-{length:04}', baseline[:length])
    for limit in ['vertices', 'chunks', 'file', 'frames', 'materials', 'totals', 'uv', 'bones']:
        add('limit-' + limit, baseline, limits=limit)
    full_models = {'bmori', 'army', 'infernus', 'colt45', 'nrg500', 'bmx', 'dodo',
                   'predator', 'freight', 'shamal', 'landstal', 'jetpack', 'parachute', 'hat8'}
    owner_hashes, owner_rejections = {}, []
    if not args.no_archive and args.archive.is_dir():
        for path in sorted(args.archive.glob('*.dff')):
            full = path.stem in full_models
            cases.append({'path': str(path.resolve()), 'full': full})
            try:
                expected.append(reference(path, full))
            except (AssertionError, ValueError, struct.error) as error:
                expected.append(None)
                owner_rejections.append({'file': path.name, 'referenceError': str(error)})
            owner_hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    manifest = OUT / 'manifest.json'; manifest.write_text(json.dumps(cases))
    result_path = OUT / 'results.json'
    command = ['xcrun', 'swiftc', '-O', '-module-cache-path', str(OUT / 'module-cache'),
               str(ROOT / 'ios/App/NativeRenderWareDFF.swift'),
               str(ROOT / 'smoke_native_renderware_dff.swift'), '-o', str(OUT / 'smoke-dff')]
    compilation = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / 'build.log').write_text(compilation.stdout)
    assert compilation.returncode == 0, compilation.stdout
    execution = subprocess.run([str(OUT / 'smoke-dff'), str(manifest), str(result_path)],
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / 'run.log').write_text(execution.stdout)
    assert execution.returncode == 0, execution.stdout
    results = json.loads(result_path.read_text())
    assert len(results) == len(expected)
    failures = []
    for case, actual, reference_ in zip(cases, results, expected):
        try:
            assert actual['accepted'] == (reference_ is not None), actual.get('error', 'unexpected acceptance')
            if reference_ is not None:
                compare(actual['model'], reference_)
        except AssertionError as error:
            failures.append({'path': case['path'], 'error': str(error)})
    for path, digest in owner_hashes.items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, 'owner source modified: ' + path
    report = {'cases': len(cases), 'accepted': sum(x['accepted'] for x in results),
              'rejected': sum(not x['accepted'] for x in results), 'ownerModels': len(owner_hashes),
              'fullOwnerComparisons': sum(c['full'] for c in cases[len(cases) - len(owner_hashes):]) if owner_hashes else 0,
              'ownerSourcesUnchanged': True, 'failures': failures,
              'ownerReferenceRejections': owner_rejections,
              'decoderSHA256': hashlib.sha256((ROOT / 'ios/App/NativeRenderWareDFF.swift').read_bytes()).hexdigest()}
    (OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    assert not failures, f'{len(failures)} DFF failures; inspect local-only report'


if __name__ == '__main__':
    main()
