#!/usr/bin/env python3
"""Export compact, local-only DFF rigs and complete archived ANP3 tracks.

SKN1 preserves each mesh's original bind vertices, four skin influences,
hierarchy and inverse bind matrices. CLP1 stores animation tracks once for all
pedestrians. The Swift client samples and skins them at runtime through Metal.
No game assets are written into the iOS project or GitHub source tree.
"""
import argparse
import hashlib
import json
import math
import struct
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import prepare_native_animations as animation

GAME = animation.GAME
OUTPUT = animation.OUTPUT


def archive_all_blocks():
    blocks = json.loads((GAME / 'world' / 'anims.json').read_text())['blocks']
    missing = [name for name in blocks if name != 'ped' and
               not (GAME / 'world' / ('anim.' + name + '.bin')).is_file()]
    def fetch(block):
        if not block.replace('_', '').isalnum():
            raise ValueError('Invalid animation block name')
        name = 'anim.' + block + '.bin'
        request = urllib.request.Request('https://play.samp.directory/game/world/' + name,
                                         headers={'User-Agent': 'ZGTA-SA-local-archive/1.0'})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(20_000_001)
        if len(data) > 20_000_000 or len(data) < 36 or data[:4] != b'ANP3':
            raise ValueError(f'Invalid public ANP3 block: {name}')
        path = GAME / 'world' / name
        animation.atomic_write(path, data)
        actual = set(clip_names(path))
        expected = set(value.lower() for value in blocks[block])
        if actual != expected:
            raise ValueError(f'Public animation index differs for {block}: missing={expected-actual}, extra={actual-expected}')
        return name, len(data)
    with ThreadPoolExecutor(max_workers=4) as pool:
        for name, length in pool.map(fetch, missing):
            print(f'{name}: archived {length} bytes locally', flush=True)


def matrix_bytes(row_major):
    return struct.pack('<16f', *(row_major[row * 4 + column]
                                for column in range(4) for row in range(4)))


def string_bytes(value):
    encoded = value.encode('utf-8')
    if len(encoded) > 65535:
        raise ValueError('Skeletal string exceeds format limit')
    return struct.pack('<H', len(encoded)) + encoded


def clip_names(path):
    data = path.read_bytes()
    if len(data) < 36 or data[:4] != b'ANP3':
        raise ValueError(f'Not an ANP3 archive: {path.name}')
    count = struct.unpack_from('<I', data, 32)[0]
    at = 36
    names = []
    for _ in range(count):
        if at + 36 > len(data):
            raise ValueError('Truncated animation header')
        names.append(data[at:at + 24].split(b'\0')[0].decode('ascii').lower())
        tracks = struct.unpack_from('<I', data, at + 24)[0]
        at += 36
        for _ in range(tracks):
            if at + 36 > len(data):
                raise ValueError('Truncated animation track')
            kind, frames = struct.unpack_from('<II', data, at + 24)
            if kind not in animation.KINDS:
                raise ValueError('Unsupported ANP3 frame type')
            at += 36 + animation.KINDS[kind] * frames
            if at > len(data):
                raise ValueError('Truncated animation keys')
    if at != len(data):
        raise ValueError(f'Unexpected trailing ANP3 data in {path.name}')
    return names


def export_library():
    sources = [GAME / 'world' / 'pedanims.bin'] + sorted((GAME / 'world').glob('anim.*.bin'))
    clips = {}
    digests = {}
    for path in sources:
        block = 'ped' if path.name == 'pedanims.bin' else path.name[5:-4]
        parsed = animation.clips_from_anp3(path, tuple(clip_names(path)))
        clips.update({block + '/' + name: value for name, value in parsed.items()})
        digests[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    aliases = {name: ('ped/' + source, 'ped/idle_stance' if name in
               ('fighta_1', 'fighta_2', 'fighta_3') else '')
               for name, source in animation.PED_CLIPS.items()}
    aliases.update({name: ('swim/' + source, '') for name, source in animation.SWIM_CLIPS.items()})
    aliases.update({name: (block + '/' + source, 'ped/weapon_crouch' if 'crouch' in source else
                   'ped/gun_stand') for block, values in animation.WEAPON_CLIPS.items()
                   for name, source in values.items()})
    for name, (source, base) in aliases.items():
        if source not in clips or base and base not in clips:
            raise ValueError(f'Alias has an unavailable source: {name}')
    result = bytearray(struct.pack('<4sIII', b'CLP1', len(clips), len(aliases), 1))
    key_count = 0
    for name, (duration, tracks) in sorted(clips.items()):
        result.extend(string_bytes(name))
        result.extend(struct.pack('<fI', duration, len(tracks)))
        for bone, keys in sorted(tracks.items()):
            positioned = any(key[2] is not None for key in keys)
            result.extend(struct.pack('<iII', bone, len(keys), int(positioned)))
            for time, rotation, translation in keys:
                values = (time, *rotation, *((translation or (0., 0., 0.)) if positioned else ()))
                if not all(math.isfinite(value) for value in values):
                    raise ValueError(f'Non-finite ANP3 key: {name}/{bone}')
                result.extend(struct.pack('<' + 'f' * len(values), *values))
                key_count += 1
    for name, (source, base) in sorted(aliases.items()):
        result.extend(string_bytes(name) + string_bytes(source) + string_bytes(base))
    animation.atomic_write(OUTPUT / 'animations.clips.bin', result)
    metadata = {'format': 'CLP1', 'revision': 1, 'clips': len(clips), 'aliases': len(aliases),
                'keys': key_count, 'bytes': len(result),
                'sha256': hashlib.sha256(result).hexdigest(), 'sources': digests}
    index = json.loads((GAME / 'world' / 'anims.json').read_text())['blocks']
    indexed = {block + '/' + name.lower() for block, values in index.items() for name in values}
    metadata['indexedClips'] = len(indexed)
    metadata['missingIndexedClips'] = sorted(indexed - set(clips))
    metadata['extraIndexedClips'] = sorted(set(clips) - indexed)
    animation.atomic_write(OUTPUT / 'animations.clips.json', json.dumps(metadata, indent=2).encode())
    return metadata


def export_skeleton(name):
    frames, bone_frames, nodes, atomic, points, order, indices, weights, inverse, floor = \
        animation.pedestrian_data(GAME / (name + '.dff'))
    if [index for _, index, _ in nodes] != list(range(len(nodes))):
        raise ValueError(f'Unsupported skin palette order: {name}')
    bind = animation.global_matrices(frames, bone_frames, {}, 0)
    basis = animation.multiply(bind[bone_frames[nodes[0][0]]], inverse[0])
    correction = animation.multiply(bind[atomic], animation.inverse_rigid(basis))
    axis = (1., 0., 0., 0., 0., 0., -1., 0., 0., 1., 0., -floor, 0., 0., 0., 1.)
    by_frame = {frame: bone for bone, frame in bone_frames.items()}
    result = bytearray(struct.pack('<4sIII', b'SKN1', len(order), len(frames), len(nodes)))
    result.extend(matrix_bytes(correction))
    result.extend(matrix_bytes(axis))
    for index, (values, parent) in enumerate(frames):
        if parent >= index or parent < -1:
            raise ValueError('Skeleton hierarchy is not in parent order')
        result.extend(struct.pack('<ii', parent, by_frame.get(index, -1)))
        result.extend(matrix_bytes(animation.mat(values)))
    for bone, index, _ in nodes:
        result.extend(struct.pack('<I', bone_frames[bone]))
        result.extend(matrix_bytes(inverse[index]))
    for vertex in order:
        if abs(sum(weights[vertex]) - 1) > 0.01 or max(indices[vertex]) >= len(nodes):
            raise ValueError('Invalid skin influences')
        result.extend(struct.pack('<3f4B4f', *points[vertex], *indices[vertex], *weights[vertex]))
    path = OUTPUT / (name + '.skel.bin')
    animation.atomic_write(path, result)
    return {'vertices': len(order), 'frames': len(frames), 'bones': len(nodes),
            'bytes': len(result), 'sha256': hashlib.sha256(result).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--archive-missing', action='store_true')
    parser.add_argument('--archive-all-blocks', action='store_true',
                        help='Archive every public ANP3 block listed by the local game animation index')
    parser.add_argument('models', nargs='*')
    args = parser.parse_args()
    if args.archive_missing:
        animation.archive_missing()
    if args.archive_all_blocks:
        archive_all_blocks()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    library = export_library()
    if args.archive_all_blocks and library['missingIndexedClips']:
        raise ValueError('The public animation index still has missing clips')
    print(f'CLP1: {library["clips"]} clips, {library["keys"]} keys, {library["bytes"]} bytes', flush=True)
    pedestrians = set(json.loads((OUTPUT / 'index.json').read_text())['peds'].values())
    names = sorted(pedestrians if args.all else set(args.models or ['bmori']) & pedestrians)
    path = OUTPUT / 'skeletons.json'
    metadata = json.loads(path.read_text()) if path.is_file() else {}
    for name in names:
        metadata[name] = export_skeleton(name)
    animation.atomic_write(path, json.dumps(metadata, sort_keys=True, indent=2).encode())
    animation.init_worker()
    animation.write_pedestrian_metadata(names, animation.WORKER_CLIPS)
    print(f'SKN1: {len(metadata)} pedestrian rigs, {sum(row["bytes"] for row in metadata.values())} bytes', flush=True)


if __name__ == '__main__':
    main()
