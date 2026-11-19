#!/usr/bin/env python3
"""Bake locally archived San Andreas pedestrian clips for the native client.

The source DFF and ANP3 files and the generated vertex frames stay under
ignored local-only/. No game data is placed in the iOS project or GitHub.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import hashlib
import json
import math
import os
import struct
import tempfile
import urllib.request
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from tools.assets.prepare_native_models import GAME, OUTPUT, chunks, children, first, frame_list, geometry, transform

try:
    import numpy as np
except ImportError:
    np = None

# Short aliases fit the ANM1/HND1 fixed-width clip field. Every source name is
# resolved against ANP3 bytes, never inferred from a similar filename.
PED_CLIPS = {
    name: name for name in ('idle_stance', 'walk_player', 'run_player',
                           'jump_launch', 'jump_glide', 'jump_land', 'fall_fall',
                           'fall_land', 'gun_stand', 'fighta_1', 'fighta_2',
                           'fighta_3', 'weapon_crouch', 'guncrouchfwd',
                           'guncrouchbwd', 'car_getin_lhs', 'car_getout_lhs',
                           'car_sit', 'climb_pull', 'climb_stand', 'sprint_civi')
}
PED_CLIPS.update({'death_front': 'ko_shot_front', 'hit_front': 'hit_front',
                  'duck_idle': 'duck_cower'})
SWIM_CLIPS = {name: name for name in ('swim_tread', 'swim_breast', 'swim_crawl',
                                     'swim_under', 'swim_glide')}
SWIM_CLIPS['swim_dive'] = 'swim_dive_under'
WEAPON_CLIPS = {
    'colt45': {'colt45_fire': 'colt45_fire', 'colt45_reload': 'colt45_reload',
               'pistol_cfire': 'colt45_crouchfire', 'pistol_creload': 'colt45_crouchreload',
               'sawnoff_reload': 'sawnoff_reload'},
    'python': {'python_fire': 'python_fire', 'python_reload': 'python_reload',
               'python_cfire': 'python_crouchfire', 'python_creload': 'python_crouchreload'},
    'silenced': {'silence_fire': 'silence_fire', 'silence_reload': 'silence_reload',
                 'silence_cfire': 'silencecrouchfire', 'silence_creload': 'crouchreload'},
    'shotgun': {'shotgun_fire': 'shotgun_fire', 'shotgun_cfire': 'shotgun_crouchfire'},
    'buddy': {'buddy_fire': 'buddy_fire', 'buddy_reload': 'buddy_reload',
              'buddy_cfire': 'buddy_crouchfire', 'buddy_creload': 'buddy_crouchreload'},
    'uzi': {'uzi_fire': 'uzi_fire', 'uzi_reload': 'uzi_reload',
            'uzi_cfire': 'uzi_crouchfire', 'uzi_creload': 'uzi_crouchreload'},
    'rifle': {'rifle_fire': 'rifle_fire', 'rifle_load': 'rifle_load',
              'rifle_cfire': 'rifle_crouchfire', 'rifle_cload': 'rifle_crouchload'},
    'baseball': {'bat_1': 'bat_1', 'bat_idle': 'bat_idle'},
    'chainsaw': {'csaw_1': 'csaw_1', 'idle_csaw': 'idle_csaw'},
}
CLIPS = tuple(PED_CLIPS) + tuple(SWIM_CLIPS) + tuple(
    alias for block in WEAPON_CLIPS.values() for alias in block)
LOOPING = {'idle_stance', 'walk_player', 'run_player', 'sprint_civi',
           'gun_stand', 'weapon_crouch', 'guncrouchfwd', 'guncrouchbwd',
           'duck_idle', 'jump_glide', 'fall_fall', 'car_sit',
           'swim_tread', 'swim_breast', 'swim_crawl', 'swim_under', 'swim_glide',
           'bat_idle', 'idle_csaw'}
KINDS = {1: 20, 2: 32, 3: 10, 4: 16}
WORKER_CLIPS = None
FORCE = False
ANIMATION_REVISION = 3


def source_paths():
    return [GAME / 'world' / 'pedanims.bin', GAME / 'world' / 'anim.swim.bin'] + [
        GAME / 'world' / f'anim.{block}.bin' for block in WEAPON_CLIPS]


def archive_missing():
    for path in source_paths():
        if path.is_file():
            continue
        request = urllib.request.Request('https://play.samp.directory/game/world/' + path.name,
                                         headers={'User-Agent': 'ZGTA-SA-local-archive/1.0'})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(20_000_001)
        if len(data) > 20_000_000 or len(data) < 36 or data[:4] != b'ANP3':
            raise ValueError(f'Invalid public animation data: {path.name}')
        path.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(path, data)
        print(f'{path.name}: archived {len(data)} bytes locally', flush=True)


def mat(values, padded=False):
    groups = ((0, 4, 8, 12) if padded else (0, 3, 6, 9))
    return tuple((values[groups[j] + i] if i < 3 else (1.0 if j == 3 else 0.0))
                 for i in range(4) for j in range(4))


def multiply(a, b):
    if np is not None:
        return tuple((np.asarray(a).reshape((4, 4)) @
                      np.asarray(b).reshape((4, 4))).reshape(-1).tolist())
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


def clips_from_anp3(path, wanted=CLIPS):
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
        keep = name in wanted
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
            if keep and bone >= 0 and frames:
                keys = []
                for n in range(frames):
                    offset = at + n * size
                    if kind in (3, 4):
                        q = tuple(x / 4096 for x in struct.unpack_from('<4h', data, offset))
                        time = struct.unpack_from('<h', data, offset+8)[0] / 60
                    else:
                        q = struct.unpack_from('<4f', data, offset)
                        time = struct.unpack_from('<f', data, offset+16)[0]
                    translation = tuple(x / 1024 for x in struct.unpack_from('<3h', data, offset+10)) if kind == 4 else \
                        struct.unpack_from('<3f', data, offset+20) if kind == 2 else None
                    keys.append((time, q, translation))
                duration = max(duration, keys[-1][0])
                tracks[bone] = keys
            at += size * frames
        if keep:
            result[name] = (duration, tracks)
    if set(result) != set(wanted):
        raise ValueError(f'Missing native pedestrian clips: {set(wanted) - set(result)}')
    return result


def sample(keys, time):
    if time <= keys[0][0]:
        return keys[0][1]
    for n in range(1, len(keys)):
        end, right = keys[n][:2]
        if time <= end:
            start, left = keys[n-1][:2]
            alpha = max(0.0, min(1.0, (time-start) / max(1e-6, end-start)))
            left_length = math.sqrt(sum(value * value for value in left))
            right_length = math.sqrt(sum(value * value for value in right))
            if left_length < 1e-8 or right_length < 1e-8:
                raise ValueError('Zero animation quaternion')
            left = tuple(value / left_length for value in left)
            right = tuple(value / right_length for value in right)
            dot = sum(left[i]*right[i] for i in range(4))
            if dot < 0:
                right = tuple(-x for x in right)
                dot = -dot
            # The archived ANP3 player (9368) uses Quaternion.slerp. Linear
            # quaternion blending visibly changes sparse firearm tracks.
            if dot >= 0.999999:
                return tuple((1-alpha)*left[i] + alpha*right[i] for i in range(4))
            angle = math.acos(max(-1., min(1., dot)))
            sine = math.sin(angle)
            return tuple((math.sin((1-alpha)*angle)*left[i] +
                          math.sin(alpha*angle)*right[i]) / sine for i in range(4))
    return keys[-1][1]


def sample_translation(keys, time):
    positioned = [(key[0], key[2]) for key in keys if len(key) > 2 and key[2] is not None]
    if not positioned:
        return (0., 0., 0.)
    if time <= positioned[0][0]:
        return positioned[0][1]
    for index in range(1, len(positioned)):
        end, right = positioned[index]
        if time <= end:
            start, left = positioned[index - 1]
            alpha = max(0., min(1., (time - start) / max(1e-6, end - start)))
            return tuple((1-alpha)*left[i] + alpha*right[i] for i in range(3))
    return positioned[-1][1]


def root_transform(tracks, time, reference, floor):
    """Apply bone-0 tilt and height while leaving horizontal travel to physics.

    ANP3's root keys are in game coordinates. DFF bone 0 instead carries a
    fixed basis permutation, which must stay intact while skinning. Applying
    the relative rotation after the DFF-to-game transform preserves that basis
    and pivots the body around its root rather than around its feet.
    """
    keys = tracks.get(0)
    if not keys:
        return quat_mat((0., 0., 0., 1.), (0., 0., 0.))
    orientation = multiply(quat_mat(sample(keys, time), (0., 0., 0.)),
                           inverse_rigid(quat_mat(sample(reference, 0), (0., 0., 0.))))
    height = sample_translation(keys, time)[2] - sample_translation(reference, 0)[2]
    pivot = (0., 0., -floor)
    shifted = list(orientation)
    rotated = apply(orientation, pivot)
    for axis in range(3):
        shifted[axis * 4 + 3] = pivot[axis] - rotated[axis] + (height if axis == 2 else 0.)
    return tuple(shifted)


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
                keys = tracks[bone]
                place = sample_translation(keys, time) if any(key[2] is not None for key in keys) else values[9:12]
                local = quat_mat(sample(keys, time), place)
        globals_[index] = multiply(globals_[parent], local) if parent >= 0 else local
    return globals_


def pose(globals_, bone_frames, bone_nodes, inverse_bones, correction):
    return [multiply(correction,
                     multiply(globals_[bone_frames[node]], inverse_bones[index]))
            for node, index, _ in bone_nodes]


def bake(path, destination, clips, fps=30, selected=None):
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
    names = tuple(clips) if selected is None else tuple(selected)
    result = bytearray(struct.pack('<4sIII', b'ANM1', len(order), len(names), fps))
    hands = bytearray(struct.pack('<4sIII', b'HND1', len(names), fps, 0))
    axis_transform = (1., 0., 0., 0., 0., 0., -1., 0., 0., 1., 0., -floor, 0., 0., 0., 1.)
    if np is not None:
        vertex_points = np.asarray([points[index] for index in order], dtype=np.float64)
        vertex_bones = np.asarray([indices[index] for index in order])
        vertex_weights = np.asarray([weights[index] for index in order], dtype=np.float64)
    for name in names:
        if len(name.encode('ascii')) > 16:
            raise ValueError(f'Clip alias exceeds ANM1 name field: {name}')
        duration, tracks = clips[name]
        frame_count = max(1, math.ceil(duration * fps) + (0 if name in LOOPING else 1))
        result.extend(struct.pack('<16sI', name.encode('ascii'), frame_count))
        hands.extend(struct.pack('<16sI', name.encode('ascii'), frame_count))
        for frame in range(frame_count):
            globals_ = global_matrices(frames, bone_frames, tracks, frame / fps)
            palette = pose(globals_, bone_frames, bone_nodes, inv, correction)
            root = root_transform(tracks, frame / fps, clips['idle_stance'][1][0], floor)
            hand = multiply(root, multiply(axis_transform, multiply(correction, globals_[bone_frames[26]])))
            hands.extend(struct.pack('<16f', *(hand[row * 4 + col]
                                                  for col in range(4) for row in range(4))))
            if np is not None:
                matrices = np.asarray(palette, dtype=np.float64).reshape((-1, 4, 4))[vertex_bones]
                transformed = np.einsum('nvij,nj->nvi', matrices[:, :, :3, :3], vertex_points)
                transformed += matrices[:, :, :3, 3]
                skinned = np.sum(transformed * vertex_weights[:, :, None], axis=1)
                native = np.column_stack((skinned[:, 0], -skinned[:, 2], skinned[:, 1] - floor))
                root_matrix = np.asarray(root, dtype=np.float64).reshape((4, 4))
                native = native @ root_matrix[:3, :3].T + root_matrix[:3, 3]
                result.extend(native.astype('<f4').tobytes())
                continue
            for vertex in order:
                point = points[vertex]
                skinned = [0.0, 0.0, 0.0]
                for bone, weight in zip(indices[vertex], weights[vertex]):
                    if weight <= 0:
                        continue
                    moved = apply(palette[bone], point)
                    for axis in range(3):
                        skinned[axis] += weight * moved[axis]
                vertex = apply(root, (skinned[0], -skinned[2], skinned[1] - floor))
                result.extend(struct.pack('<3f', *vertex))
    destination.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(destination, result)
    hand_path = destination.with_name(path.stem + '.hand.bin')
    atomic_write(hand_path, hands)
    atomic_write(destination.with_name(path.stem + '.anim.json'), json.dumps({
        'revision': ANIMATION_REVISION, 'clips': len(names),
        'animationSHA256': hashlib.sha256(result).hexdigest(),
        'handSHA256': hashlib.sha256(hands).hexdigest()}, sort_keys=True).encode())
    return len(order), len(result), static_error


def atomic_write(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + '.', delete=False) as temporary:
        temporary.write(data)
        staged = Path(temporary.name)
    try:
        os.chmod(staged, 0o600)
        staged.replace(path)
    finally:
        staged.unlink(missing_ok=True)


def pedestrian_metadata(name, clips):
    frames, bone_frames, bone_nodes, atomic_frame, points, order, _, _, inv, floor = \
        pedestrian_data(GAME / f'{name}.dff')
    bind = global_matrices(frames, bone_frames, {}, 0)
    basis = multiply(bind[bone_frames[bone_nodes[0][0]]], inv[0])
    correction = multiply(bind[atomic_frame], inverse_rigid(basis))
    axis = (1., 0., 0., 0., 0., 0., -1., 0., 0., 1., 0., -floor, 0., 0., 0., 1.)
    result = {}
    samples = {'standing': ('idle_stance', 0), 'car_sit': ('car_sit', 0),
               'entryStart': ('car_getin_lhs', 0), 'entryEnd': ('car_getin_lhs', None),
               'exitStart': ('car_getout_lhs', 0), 'exitEnd': ('car_getout_lhs', None)}
    for label, (clip, instant) in samples.items():
        duration, tracks = clips[clip]
        time = duration if instant is None else instant
        globals_ = global_matrices(frames, bone_frames, tracks, time)
        root = root_transform(tracks, time, clips['idle_stance'][1][0], floor)
        pelvis = multiply(root, multiply(axis, multiply(correction, globals_[bone_frames[1]])))
        result[label] = [round(value, 6) for value in apply(pelvis, (0., 0., 0.))]
    result['height'] = round(max(transform(points[index], frames, atomic_frame)[1]
                                 for index in order) - floor, 6)
    return result


def write_pedestrian_metadata(names, clips):
    path = OUTPUT / 'pedestrians.json'
    metadata = json.loads(path.read_text()) if path.is_file() else {}
    for name in names:
        metadata[name] = pedestrian_metadata(name, clips)
    atomic_write(path, json.dumps(metadata, sort_keys=True, separators=(',', ':')).encode())
    print(f'pedestrians.json: {len(metadata)} model pelvis anchors', flush=True)


def init_worker(force=False):
    global WORKER_CLIPS, FORCE
    FORCE = force
    source = clips_from_anp3(GAME / 'world' / 'pedanims.bin', tuple(PED_CLIPS.values()))
    base = {alias: source[name] for alias, name in PED_CLIPS.items()}
    swimming = clips_from_anp3(GAME / 'world' / 'anim.swim.bin', tuple(SWIM_CLIPS.values()))
    base.update({alias: swimming[name] for alias, name in SWIM_CLIPS.items()})
    for block, aliases in WEAPON_CLIPS.items():
        source = clips_from_anp3(GAME / 'world' / f'anim.{block}.bin', tuple(aliases.values()))
        for alias, name in aliases.items():
            duration, tracks = source[name]
            stance = 'weapon_crouch' if 'crouch' in name else 'gun_stand'
            base[alias] = (duration, {**base[stance][1], **tracks})
    for name in ('fighta_1', 'fighta_2', 'fighta_3'):
        base[name] = (base[name][0], {**base['idle_stance'][1], **base[name][1]})
    WORKER_CLIPS = base


def prepare_one(name):
    destination = OUTPUT / f'{name}.anim.bin'
    revision_path = destination.with_name(name + '.anim.json')
    revision = json.loads(revision_path.read_text()).get('revision') if revision_path.is_file() else None
    if destination.is_file() and destination.with_name(name + '.hand.bin').is_file() and \
            revision == ANIMATION_REVISION and not FORCE:
        with destination.open('rb') as stream:
            header = stream.read(16)
        with destination.with_name(name + '.hand.bin').open('rb') as stream:
            hand_header = stream.read(16)
        if len(header) == 16 and len(hand_header) == 16 and \
                struct.unpack('<4sIII', header)[2] == len(WORKER_CLIPS) and \
                struct.unpack('<4sIII', hand_header)[1] == len(WORKER_CLIPS):
            return f'{name}: already baked'
    try:
        count, size, error = bake(GAME / f'{name}.dff', destination, WORKER_CLIPS)
        return f'{name}: {count} animated vertices, {size} bytes, bind error {error:.5f} m'
    except (ValueError, struct.error, KeyError) as problem:
        return f'{name}: skipped ({problem})'


def frame_sections(data):
    magic, a, b, c = struct.unpack_from('<4sIII', data)
    if magic == b'ANM1':
        count, stride = b, a * 12
    elif magic == b'HND1':
        count, stride = a, 64
    else:
        raise ValueError('Invalid frame file for clip patch')
    at, sections = 16, []
    for _ in range(count):
        name = data[at:at+16].split(b'\0')[0].decode('ascii')
        frames = struct.unpack_from('<I', data, at+16)[0]
        end = at + 20 + frames * stride
        if end > len(data):
            raise ValueError('Truncated frame file for clip patch')
        sections.append((name, data[at:end]))
        at = end
    if at != len(data):
        raise ValueError('Unexpected frame file length for clip patch')
    return sections


def patch_one(name, selected):
    with tempfile.TemporaryDirectory(dir=OUTPUT, prefix='clip-patch-') as temporary:
        staged = Path(temporary) / (name + '.anim.bin')
        bake(GAME / (name + '.dff'), staged, WORKER_CLIPS, selected=selected)
        updated = []
        for suffix in ('anim.bin', 'hand.bin'):
            path = OUTPUT / (name + '.' + suffix)
            old = path.read_bytes()
            replacements = dict(frame_sections((Path(temporary) / (name + '.' + suffix)).read_bytes()))
            sections = frame_sections(old)
            if not set(replacements).issubset({key for key, _ in sections}):
                raise ValueError('Clip patch cannot add unlisted clips')
            data = old[:16] + b''.join(replacements.get(key, value) for key, value in sections)
            atomic_write(path, data)
            updated.append(data)
        atomic_write(OUTPUT / (name + '.anim.json'), json.dumps({
            'revision': ANIMATION_REVISION, 'clips': len(WORKER_CLIPS),
            'animationSHA256': hashlib.sha256(updated[0]).hexdigest(),
            'handSHA256': hashlib.sha256(updated[1]).hexdigest()}, sort_keys=True).encode())
    return f'{name}: patched ' + ', '.join(selected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all', action='store_true', help='Bake every locally converted pedestrian')
    parser.add_argument('--force', action='store_true', help='Rebake existing local files')
    parser.add_argument('--archive-missing', action='store_true',
                        help='Fetch missing public animation blocks into ignored local-only game data')
    parser.add_argument('--metadata-only', action='store_true',
                        help='Refresh per-model pelvis anchors without rebaking vertex frames')
    parser.add_argument('--patch-clips', nargs='+',
                        help='Rebake only these existing clip aliases while preserving other frame sections')
    parser.add_argument('models', nargs='*', help='DFF names, e.g. bmori')
    args = parser.parse_args()
    if args.archive_missing:
        archive_missing()
    index = json.loads((OUTPUT / 'index.json').read_text())
    pedestrians = set(index['peds'].values())
    names = pedestrians if args.all else (set(args.models) or {'bmori'})
    selected = sorted(names & pedestrians)
    init_worker(args.force)
    wire_names = {alias: 'ped/' + name for alias, name in PED_CLIPS.items()}
    wire_names.update({alias: 'swim/' + name for alias, name in SWIM_CLIPS.items()})
    wire_names.update({alias: block + '/' + name for block, aliases in WEAPON_CLIPS.items()
                       for alias, name in aliases.items()})
    manifest = {'format': 'ANM1', 'revision': ANIMATION_REVISION, 'fps': 30,
                'source': {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in source_paths()}, 'clips': {
        name: {'duration': round(duration, 6), 'loop': name in LOOPING, 'wire': wire_names[name]}
        for name, (duration, _) in WORKER_CLIPS.items()}}
    atomic_write(OUTPUT / 'animations.json', json.dumps(manifest, indent=2).encode())
    write_pedestrian_metadata(selected, WORKER_CLIPS)
    if args.metadata_only:
        return
    if args.patch_clips:
        if not set(args.patch_clips).issubset(WORKER_CLIPS):
            raise ValueError('Unknown clip alias for patch')
        for name in selected:
            print(patch_one(name, args.patch_clips), flush=True)
        return
    workers = min(8, os.cpu_count() or 4) if args.all else 1
    if workers == 1:
        for name in selected:
            print(prepare_one(name), flush=True)
    else:
        with ProcessPoolExecutor(max_workers=workers, initializer=init_worker,
                                 initargs=(args.force,)) as pool:
            for result in pool.map(prepare_one, selected):
                print(result, flush=True)


if __name__ == '__main__':
    main()
