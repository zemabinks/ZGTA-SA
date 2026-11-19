#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Check native custom-ped SKN1 output against our independent Python exporter.

Original DFFs and all derived skeleton goldens stay in local-only. Generated
fixtures exercise frame/palette reordering and material splits without assets.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys

import tools.assets.prepare_native_models as models
import tools.assets.prepare_native_animations as animation
import tools.assets.prepare_native_skeletons as skeletons
from tests.resources.smoke_native_renderware_dff import chunk, pack, synthetic, static_synthetic

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'local-only/research/runtime-skeleton'


def fixture(order=(0, 1, 2), reverse_palette=False, scale=1., root_id=0, pelvis_id=1,
            inverse_scale=1., empty=False, extreme=False):
    identity = [1., 0., 0., 0., 1., 0., 0., 0., 1., 0., 0., 0.]
    matrices = [identity[:], identity[:], identity[:]]
    matrices[0][0] = scale
    matrices[2][10] = .5
    remap = {source: target for target, source in enumerate(order)}
    parents = [-1, 0, 1]
    frames = pack('I', 3)
    for source in order:
        frames += pack('12fiI', *matrices[source], remap[parents[source]] if parents[source] >= 0 else -1, 0)
    nodes = [(root_id, 0, 0), (pelvis_id, 1, 0)]
    if reverse_palette:
        nodes.reverse()
    hierarchy = pack('5I', 0x100, root_id, 2, 0, 36) + b''.join(pack('3I', *node) for node in nodes)
    extensions = [chunk(3), chunk(3, chunk(0x11e, hierarchy)),
                  chunk(3, chunk(0x11e, pack('3I', 0x100, pelvis_id, 0)))]
    frame_list = chunk(14, chunk(1, frames) + b''.join(extensions[source] for source in order))
    faces = [] if empty else [(0, 1, 2, 0), (0, 2, 3, 1)]
    points = [(1001. if extreme else 0., -1., 0.), (1., -1., 0.), (0., 1., 0.), (0., -1., 1.)]
    geometry = pack('HBBIII', 2, 0, 0, len(faces), 4, 1)
    geometry += b''.join(pack('4H', b, a, mat, c) for a, b, c, mat in faces)
    geometry += pack('4fII', 0, 0, 0, 2, 1, 0) + b''.join(pack('3f', *point) for point in points)
    material = chunk(7, chunk(1, pack('I4BII3f', 0, 100, 120, 140, 255, 0, 0, 1, 1, 1)) + chunk(3))
    materials = chunk(8, chunk(1, pack('Iii', 2, -1, 0)) + material)
    skin = pack('4B2B', 2, 2, 1, 0, 0, 1) + bytes([0, 0, 0, 0] + [1, 0, 0, 0] * 3)
    skin += pack('16f', *([1., 0., 0., 0.] * 4))
    for bone in range(2):
        skin += pack('16f', inverse_scale, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -.5 * bone, 0, 0)
    skin += pack('3I', 0, 0, 0)
    geometries = chunk(26, chunk(1, pack('I', 1)) + chunk(15, chunk(1, geometry) + materials + chunk(3, chunk(0x116, skin))))
    atomic = chunk(20, chunk(1, pack('4I', remap[0], 0, 5, 0)) + chunk(3))
    return chunk(16, chunk(1, pack('3I', 1, 0, 0)) + frame_list + geometries + atomic + chunk(3))


def generated_expected():
    """Hand-authored SKN1 for the original unit-basis fixture, no parser reuse."""
    identity = [1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.]
    axis = [1., 0., 0., 0., 0., 0., 1., 0., 0., -1., 0., 0., 0., 0., 1., 1.]
    out = bytearray(b'SKN1' + pack('3I', 6, 3, 2) + pack('32f', *(identity + axis)))
    for parent, bone, y in [(-1, -1, 0), (0, 0, 0), (1, 1, .5)]:
        matrix = identity[:]; matrix[13] = y
        out += pack('ii16f', parent, bone, *matrix)
    for frame, y in [(1, 0), (2, -.5)]:
        matrix = identity[:]; matrix[13] = y
        out += pack('I16f', frame, *matrix)
    positions = [(0., -1., 0.), (1., -1., 0.), (0., 1., 0.), (0., -1., 1.)]
    for source in [0, 1, 2, 0, 2, 3]:
        out += pack('3f4B4f', *positions[source], 0 if source == 0 else 1, 0, 0, 0, 1., 0., 0., 0.)
    return bytes(out)


def fields(data):
    assert data[:4] == b'SKN1'
    vertices, frame_count, bones = struct.unpack_from('<3I', data, 4)
    at = 16
    floats, integers = [], [vertices, frame_count, bones]
    def matrix():
        nonlocal at
        value = struct.unpack_from('<16f', data, at); at += 64; floats.extend(value)
        return animation.mat(value, True)
    correction, axis = matrix(), matrix()
    frames = []
    for _ in range(frame_count):
        parent, bone = struct.unpack_from('<ii', data, at); at += 8; integers.extend([parent, bone])
        rest = matrix(); frames.append((parent, rest))
    palette = []
    for _ in range(bones):
        frame = struct.unpack_from('<I', data, at)[0]; at += 4; integers.append(frame)
        palette.append((frame, matrix()))
    points, influences = [], []
    for _ in range(vertices):
        values = struct.unpack_from('<3f4B4f', data, at); at += 32
        floats.extend(values[:3]); integers.extend(values[3:7]); floats.extend(values[7:])
        points.append(values[:3]); influences.append((values[3:7], values[7:]))
    assert at == len(data)
    globals_ = []
    for parent, rest in frames:
        globals_.append(animation.multiply(globals_[parent], rest) if parent >= 0 else rest)
    native = animation.multiply(axis, correction)
    palette = [animation.multiply(animation.multiply(native, globals_[frame]), inverse) for frame, inverse in palette]
    rest_points = []
    for point, (ids, weights) in zip(points, influences):
        transformed = [animation.apply(palette[bone], point) for bone in ids]
        rest_points.append([sum(transformed[i][axis_] * weights[i] for i in range(4)) for axis_ in range(3)])
    return integers, floats, rest_points


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # export_skeleton writes a file and returns metadata. Redirect its output
    # before calling it; never write through local-only/site's archive symlink.
    skeletons.OUTPUT = OUT / 'reference-export'
    skeletons.OUTPUT.mkdir(exist_ok=True)
    animation.OUTPUT = skeletons.OUTPUT
    models.OUTPUT = skeletons.OUTPUT
    cases, expected, vertex_orders, index_orders, owner_hashes = [], [], [], [], {}
    def add(name, data, golden=None, limit=None):
        path = OUT / (name + '.dff'); path.write_bytes(data)
        cases.append({'path': str(path), 'limit': limit}); expected.append(golden)
        vertex_orders.append([[0, 0], [1, 0], [2, 0], [0, 1], [2, 1], [3, 1]] if golden is not None else None)
        index_orders.append([0, 1, 2, 3, 4, 5] if golden is not None else None)
    golden = generated_expected()
    add('generated-material-split', fixture(), golden)
    add('generated-frame-reordering', fixture(order=(2, 0, 1)), golden)
    add('generated-palette-reordering', fixture(reverse_palette=True), golden)
    add('generated-both-reorderings', fixture(order=(2, 0, 1), reverse_palette=True), golden)
    for name, data in [('no-skin', static_synthetic()), ('morph-animation', synthetic()),
                       ('scaled-frame', fixture(scale=2)), ('reflected-frame', fixture(scale=-1)),
                       ('missing-root', fixture(root_id=2)), ('missing-pelvis', fixture(pelvis_id=2)),
                       ('scaled-inverse-bind', fixture(inverse_scale=2)),
                       ('empty-triangles', fixture(empty=True)), ('extreme-coordinates', fixture(extreme=True))]:
        add('reject-' + name, data)
    for limit in ['vertices', 'frames', 'bones', 'indices']:
        add('limit-' + limit, fixture(), limit=limit)
    # Select every actual 32-bone pedestrian, excluding static/vehicle clumps.
    archive = ROOT / 'local-only/site/game'
    if '--no-archive' not in sys.argv and archive.is_dir():
        for path in sorted(archive.glob('*.dff')):
            data = path.read_bytes()
            try:
                parts = models.children(data, models.first(list(models.chunks(data, 0, len(data))), 16))
                geometries = [c for c in models.children(data, models.first(parts, 26)) if c[0] == 15]
                if len(geometries) != 1 or len([c for c in parts if c[0] == 20]) != 1:
                    continue
                ext = models.first(models.children(data, geometries[0]), 3)
                skin = models.first(models.children(data, ext), 0x116) if ext else None
                if not skin or data[skin[1]] != 32:
                    continue
            except (TypeError, ValueError):
                continue
            owner_hashes[str(path)] = hashlib.sha256(data).hexdigest()
            metadata = skeletons.export_skeleton(path.stem)
            reference = (skeletons.OUTPUT / (path.stem + '.skel.bin')).read_bytes()
            assert hashlib.sha256(reference).hexdigest() == metadata['sha256']
            (OUT / (path.stem + '-reference.skn')).write_bytes(reference)
            cases.append({'path': str(path.resolve())}); expected.append(reference)
            ped = animation.pedestrian_data(path)
            geometry = models.geometry(data, geometries[0])
            lookup, order, indices = {}, [], []
            for a, b, c, material in geometry[1]:
                for index in (a, b, c):
                    key = (index, material)
                    if key not in lookup:
                        lookup[key] = len(order); order.append(list(key))
                    indices.append(lookup[key])
            assert [index for index, _ in order] == ped[5]
            vertex_orders.append(order); index_orders.append(indices)
    manifest = OUT / 'manifest.json'; manifest.write_text(json.dumps(cases))
    command = ['xcrun', 'swiftc', '-O', '-module-cache-path', str(OUT / 'module-cache'),
               str(ROOT / 'ios/App/NativeRenderWareDFF.swift'), str(ROOT / 'ios/App/NativeRenderWareSkeleton.swift'),
               str(ROOT / 'tests/resources/smoke_native_renderware_skeleton.swift'), '-o', str(OUT / 'smoke-skeleton')]
    compile_ = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (OUT / 'build.log').write_text(compile_.stdout); assert compile_.returncode == 0, compile_.stdout
    run = subprocess.run([str(OUT / 'smoke-skeleton'), str(manifest), str(OUT)],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (OUT / 'run.log').write_text(run.stdout); assert run.returncode == 0, run.stdout
    results = json.loads((OUT / 'results.json').read_text())
    failures, exact, maximum_error = [], 0, 0.
    for case, actual, reference, order, indices in zip(cases, results, expected, vertex_orders, index_orders):
        try:
            assert actual['accepted'] == (reference is not None), actual.get('error', 'unexpected acceptance')
            if reference is None:
                continue
            encoded = Path(actual['skn']).read_bytes()
            a_int, a_float, _ = fields(encoded); e_int, e_float, expected_points = fields(reference)
            assert a_int == e_int and len(a_float) == len(e_float), 'SKN1 integer layout mismatch'
            for a, b in zip(a_float, e_float):
                assert math.isclose(a, b, rel_tol=2e-5, abs_tol=2e-5), ('SKN1 float mismatch', a, b)
                maximum_error = max(maximum_error, abs(a-b))
            assert actual['vertexOrder'] == order and actual['indices'] == indices, 'material split/index order mismatch'
            for point, expected_point in zip(actual['restPoints'], expected_points):
                for a, b in zip(point, expected_point):
                    assert math.isclose(a, b, rel_tol=2e-5, abs_tol=2e-5), ('rest skin pose mismatch', a, b)
            exact += encoded == reference
        except AssertionError as error:
            failures.append({'path': case['path'], 'error': str(error)})
    for path, digest in owner_hashes.items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, 'owner source modified'
    report = {'cases': len(cases), 'ownerPedestrians': len(owner_hashes),
              'accepted': sum(r['accepted'] for r in results), 'rejected': sum(not r['accepted'] for r in results),
              'byteExactSKN1': exact, 'maximumFloatDifference': maximum_error,
              'ownerSourcesUnchanged': True, 'failures': failures,
              'sourceSHA256': hashlib.sha256((ROOT / 'ios/App/NativeRenderWareSkeleton.swift').read_bytes()).hexdigest()}
    (OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n'); print(json.dumps(report, indent=2))
    assert not failures, 'Skeleton bridge regression failures'


if __name__ == '__main__':
    main()
