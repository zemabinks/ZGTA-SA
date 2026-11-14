#!/usr/bin/env python3
"""Bake locally archived San Andreas pedestrian clips for the native client.

The source DFF and ANP3 files and the generated vertex frames stay under
ignored local-only/. No game data is placed in the iOS project or GitHub.
"""
import argparse
import math
import os
import struct
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from prepare_native_models import GAME, OUTPUT, chunks, children, first, frame_list, geometry, transform

CLIPS = ('idle_stance', 'walk_player', 'run_player', 'jump_launch')
KINDS = {1: 20, 2: 32, 3: 10, 4: 16}
WORKER_CLIPS = None


def mat(values, padded=False):
    groups = ((0, 4, 8, 12) if padded else (0, 3, 6, 9))
    return tuple((values[groups[j] + i] if i < 3 else (1.0 if j == 3 else 0.0))
                 for i in range(4) for j in range(4))


def multiply(a, b):
    return tuple(sum(a[i * 4 + k] * b[k * 4 + j] for k in range(4))
                 for i in range(4) for j in range(4))


def inverse_rigid(a):
    result = [0.0] * 16
    for i in range(3):
        for j in range(3):
            result[i * 4 + j] = a[j * 4 + i]
        result[i * 4 + 3] = -sum(result[i * 4 + j] * a[j * 4 + 3] for j in range(3))
    result[15] = 1.0
    return tuple(result)


def apply(a, p):
    return tuple(sum(a[i * 4 + k] * p[k] for k in range(3)) + a[i * 4 + 3]
                 for i in range(3))


def quat_mat(q, translation):
    x, y, z, w = q
    length = math.sqrt(x*x + y*y + z*z + w*w)
    if length < 1e-8:
        raise ValueError('Zero animation quaternion')
    x /= length; y /= length; z /= length; w /= length
    return (1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), translation[0],
            2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), translation[1],
            2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), translation[2],
            0, 0, 0, 1)


def clips_from_anp3(path):
    data = path.read_bytes()
    if data[:4] != b'ANP3' or len(data) < 36:
        raise ValueError('Expected ANP3 pedestrian animations')
    count = struct.unpack_from('<I', data, 32)[0]
    at = 36
    result = {}
    for _ in range(count):
        if at + 36 > len(data):
            raise ValueError('Truncated animation header')
        name = data[at:at+24].split(b'\0')[0].decode('ascii').lower()
        track_count = struct.unpack_from('<I', data, at+24)[0]
        at += 36
        keep = name in CLIPS
        tracks = {}
        duration = 0.0
        for _ in range(track_count):
            if at + 36 > len(data):
                raise ValueError('Truncated animation track')
            kind, frames, bone = struct.unpack_from('<IIi', data, at+24)
            at += 36
            size = KINDS.get(kind)
            if size is None or at + size * frames > len(data):
                raise ValueError('Unsupported animation frames')
            if keep and bone > 0 and frames:
                keys = []
                for n in range(frames):
                    offset = at + n * size
                    if kind in (3, 4):
                        q = tuple(x / 4096 for x in struct.unpack_from('<4h', data, offset))
                        time = struct.unpack_from('<h', data, offset+8)[0] / 60
                    else:
                        q = struct.unpack_from('<4f', data, offset)
                        time = struct.unpack_from('<f', data, offset+16)[0]
                    keys.append((time, q))
                duration = max(duration, keys[-1][0])
                tracks[bone] = keys
            at += size * frames
        if keep:
            result[name] = (duration, tracks)
    if set(result) != set(CLIPS):
        raise ValueError('Missing native pedestrian clips')
    return result


def sample(keys, time):
    if time <= keys[0][0]:
        return keys[0][1]
    for n in range(1, len(keys)):
        end, right = keys[n]
        if time <= end:
            start, left = keys[n-1]
            alpha = max(0.0, min(1.0, (time-start) / max(1e-6, end-start)))
            if sum(left[i]*right[i] for i in range(4)) < 0:
                right = tuple(-x for x in right)
            return tuple((1-alpha)*left[i] + alpha*right[i] for i in range(4))
    return keys[-1][1]


def pedestrian_data(path):
    data = path.read_bytes()
    clump = first(list(chunks(data, 0, len(data))), 0x10)
    parts = children(data, clump)
    frame_chunk = first(parts, 0x0e)
    frames = frame_list(data, frame_chunk)
    extensions = [item for item in children(data, frame_chunk) if item[0] == 3]
    bone_frames = {}
    bone_nodes = []
    for index, extension in enumerate(extensions):
        hanim = first(children(data, extension), 0x11e)
        if not hanim:
            continue
        _, node, count = struct.unpack_from('<III', data, hanim[1])
        bone_frames[node] = index
        if count:
            bone_nodes = [struct.unpack_from('<III', data, hanim[1]+20+n*12)
                          for n in range(count)]
    geometries = [item for item in children(data, first(parts, 0x1a)) if item[0] == 0x0f]
    atomics = []
    for item in parts:
        if item[0] == 0x14:
            info = first(children(data, item), 1)
            if info:
                atomics.append(struct.unpack_from('<II', data, info[1]))
    if len(atomics) != 1 or len(geometries) != 1 or len(bone_nodes) != 32:
        raise ValueError('Pedestrian rig shape is unsupported')
    atomic_frame, geo_index = atomics[0]
    if geo_index != 0:
        raise ValueError('Pedestrian atomic transform is unsupported')
    geo = geometries[0]
    points, faces, _, _, _ = geometry(data, geo)
    ext = first(children(data, geo), 3)
    skin = first(children(data, ext), 0x116) if ext else None
    if not skin:
        raise ValueError('Pedestrian has no skin weights')
    at = skin[1]
    bones, used, max_weights, _ = struct.unpack_from('<4B', data, at)
    at += 4 + used
    if bones != len(bone_nodes) or max_weights > 4:
        raise ValueError('Pedestrian bone counts differ')
    indices = [struct.unpack_from('<4B', data, at+n*4) for n in range(len(points))]
    at += len(points)*4
    weights = [struct.unpack_from('<4f', data, at+n*16) for n in range(len(points))]
    at += len(points)*16
    inverse_bones = [mat(struct.unpack_from('<16f', data, at+n*64), True)
                     for n in range(bones)]
    # Preserve the vertex order and material splits of prepare_native_models.
    seen = {}
    order = []
    for v1, v2, v3, material in faces:
        for vertex in (v1, v2, v3):
            key = (vertex, material)
            if key not in seen:
                seen[key] = len(order)
                order.append(vertex)
    floor = min(transform(points[index], frames, atomic_frame)[1] for index in order)
    return frames, bone_frames, bone_nodes, atomic_frame, points, order, indices, weights, inverse_bones, floor


def global_matrices(frames, bone_frames, tracks, time):
    globals_ = [None] * len(frames)
    for index, (values, parent) in enumerate(frames):
        local = mat(values)
        if index != 1:
            bone = next((node for node, frame in bone_frames.items() if frame == index), None)
            if bone is not None and bone in tracks:
                local = quat_mat(sample(tracks[bone], time), values[9:12])
        globals_[index] = multiply(globals_[parent], local) if parent >= 0 else local
    return globals_


def pose(globals_, bone_frames, bone_nodes, inverse_bones, correction):
    return [multiply(correction,
                     multiply(globals_[bone_frames[node]], inverse_bones[index]))
            for node, index, _ in bone_nodes]


def bake(path, destination, clips, fps=30):
    frames, bone_frames, bone_nodes, atomic_frame, points, order, indices, weights, inv, floor = pedestrian_data(path)
    bind_globals = global_matrices(frames, bone_frames, {}, 0)
    basis = multiply(bind_globals[bone_frames[bone_nodes[0][0]]], inv[0])
    correction = multiply(bind_globals[atomic_frame], inverse_rigid(basis))
    static_pose = pose(bind_globals, bone_frames, bone_nodes, inv, correction)
    static_error = max(
        max(abs(a-b) for a, b in zip(apply(static_pose[bone], points[vertex]),
                                    transform(points[vertex], frames, atomic_frame)))
        for vertex in order for bone, weight in zip(indices[vertex], weights[vertex]) if weight > 0
    )
    if static_error > 0.01:
        raise ValueError(f'Skin bind pose differs by {static_error:.3f} m')
    result = bytearray(struct.pack('<4sIII', b'ANM1', len(order), len(CLIPS), fps))
    for name in CLIPS:
        duration, tracks = clips[name]
        frame_count = max(1, math.ceil(duration * fps))
        result.extend(struct.pack('<16sI', name.encode('ascii'), frame_count))
        for frame in range(frame_count):
            globals_ = global_matrices(frames, bone_frames, tracks, frame / fps)
            palette = pose(globals_, bone_frames, bone_nodes, inv, correction)
            for vertex in order:
                point = points[vertex]
                skinned = [0.0, 0.0, 0.0]
                for bone, weight in zip(indices[vertex], weights[vertex]):
                    if weight <= 0:
                        continue
                    moved = apply(palette[bone], point)
                    for axis in range(3):
                        skinned[axis] += weight * moved[axis]
                result.extend(struct.pack('<3f', skinned[0], -skinned[2], skinned[1] - floor))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(result)
    return len(order), len(result), static_error


def init_worker():
    global WORKER_CLIPS
    WORKER_CLIPS = clips_from_anp3(GAME / 'world' / 'pedanims.bin')


def prepare_one(name):
    destination = OUTPUT / f'{name}.anim.bin'
    if destination.is_file():
        return f'{name}: already baked'
    try:
        count, size, error = bake(GAME / f'{name}.dff', destination, WORKER_CLIPS)
        return f'{name}: {count} animated vertices, {size} bytes, bind error {error:.5f} m'
    except (ValueError, struct.error, KeyError) as problem:
        return f'{name}: skipped ({problem})'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all', action='store_true', help='Bake every locally converted pedestrian')
    parser.add_argument('models', nargs='*', help='DFF names, e.g. bmori')
    args = parser.parse_args()
    import json
    index = json.loads((OUTPUT / 'index.json').read_text())
    pedestrians = set(index['peds'].values())
    names = pedestrians if args.all else (set(args.models) or {'bmori'})
    selected = sorted(names & pedestrians)
    workers = min(8, os.cpu_count() or 4) if args.all else 1
    if workers == 1:
        init_worker()
        for name in selected:
            print(prepare_one(name), flush=True)
    else:
        with ProcessPoolExecutor(max_workers=workers, initializer=init_worker) as pool:
            for result in pool.map(prepare_one, selected):
                print(result, flush=True)


if __name__ == '__main__':
    main()
