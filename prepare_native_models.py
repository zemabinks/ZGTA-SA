#!/usr/bin/env python3
"""Convert archived RenderWare DFF geometry into local-only WRL2 actor meshes.

The source DFF files and generated meshes stay under local-only/, which is
ignored by Git. This handles geometry, frame transforms and material colors;
animation and TXD textures require further native work.
"""
import argparse
import json
import math
import struct
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent
GAME = ROOT / 'local-only' / 'site' / 'game'
OUTPUT = GAME / 'native' / 'models'


def chunks(data, start, end):
    at = start
    while at + 12 <= end:
        kind, length, version = struct.unpack_from('<III', data, at)
        past = at + 12 + length
        if past > end or past <= at:
            raise ValueError(f'Invalid DFF chunk at {at:x}')
        yield kind, at + 12, past
        at = past
    if at != end:
        raise ValueError(f'Incomplete DFF chunk at {at:x}')


def children(data, chunk):
    return list(chunks(data, chunk[1], chunk[2]))


def first(items, kind):
    return next((item for item in items if item[0] == kind), None)


def frame_list(data, chunk):
    parts = children(data, chunk)
    info = first(parts, 1)
    if info is None:
        raise ValueError('DFF has no frame struct')
    count = struct.unpack_from('<I', data, info[1])[0]
    if count > 2000 or info[1] + 4 + count * 56 > info[2]:
        raise ValueError('Invalid frame count')
    frames = []
    for n in range(count):
        values = struct.unpack_from('<12fii', data, info[1] + 4 + n * 56)
        frames.append((values[:12], values[12]))
    return frames


def transform(point, frames, frame_number):
    visited = set()
    while frame_number >= 0:
        if frame_number >= len(frames) or frame_number in visited:
            raise ValueError('Invalid frame hierarchy')
        visited.add(frame_number)
        matrix, parent = frames[frame_number]
        x, y, z = point
        point = (matrix[0] * x + matrix[3] * y + matrix[6] * z + matrix[9],
                 matrix[1] * x + matrix[4] * y + matrix[7] * z + matrix[10],
                 matrix[2] * x + matrix[5] * y + matrix[8] * z + matrix[11])
        frame_number = parent
    return point


def materials(data, chunk):
    if chunk is None:
        return []
    parts = children(data, chunk)
    result = []
    for item in parts:
        if item[0] != 7:
            continue
        sub = children(data, item)
        info = first(sub, 1)
        rgba = data[info[1] + 4:info[1] + 8] if info else bytes([190, 190, 190, 255])
        name = ''
        texture = first(sub, 6)
        if texture:
            strings = [part for part in children(data, texture) if part[0] == 2]
            if strings:
                name = data[strings[0][1]:strings[0][2]].split(b'\0')[0].decode('ascii', 'ignore').lower()
        if any(word in name for word in ('glass', 'window', 'wind')):
            rgba = bytes([50, 75, 91, 255])
        elif any(word in name for word in ('tyre', 'tire', 'rubber')):
            rgba = bytes([34, 34, 37, 255])
        elif any(word in name for word in ('light', 'lamp')):
            rgba = bytes([224, 220, 177, 255])
        elif rgba[:3] == b'\xff\xff\xff':
            rgba = bytes([170, 170, 170, 255]) if not name else rgba
        elif rgba[1] > 220 and rgba[0] < 100 and rgba[2] < 100:
            rgba = bytes([188, 144, 32, rgba[3]])
        result.append((rgba, name))
    return result


def textures(path):
    if not path.is_file():
        return {}
    data = path.read_bytes()
    root = first(list(chunks(data, 0, len(data))), 0x16)
    if not root:
        return {}
    result = {}
    for native in children(data, root):
        if native[0] != 0x15:
            continue
        info = first(children(data, native), 1)
        if not info or info[2] - info[1] < 92:
            continue
        at = info[1]
        if struct.unpack_from('<I', data, at)[0] != 9:
            continue
        name = data[at + 8:at + 40].split(b'\0')[0].decode('ascii', 'ignore').lower()
        code = data[at + 76:at + 80]
        width, height = struct.unpack_from('<HH', data, at + 80)
        size = struct.unpack_from('<I', data, at + 88)[0]
        pixels = data[at + 92:at + 92 + size]
        if not name or not width or not height or at + 92 + size > info[2]:
            continue
        try:
            if code in (b'DXT1', b'DXT3', b'DXT5'):
                mode = {b'DXT1': 1, b'DXT3': 2, b'DXT5': 3}[code]
                image = Image.frombytes('RGBA', (width, height), pixels, 'bcn', mode)
            elif code in (struct.pack('<I', 21), struct.pack('<I', 22)) and len(pixels) == width * height * 4:
                image = Image.frombytes('RGBA', (width, height), pixels, 'raw', 'BGRA')
            else:
                continue
            result[name] = image
        except (ValueError, OSError):
            continue
    return result


def geometry(data, chunk):
    parts = children(data, chunk)
    info = first(parts, 1)
    if info is None:
        raise ValueError('DFF geometry is missing its struct')
    offset = info[1]
    flags, tex_count, _, triangle_count, vertex_count, morph_count = struct.unpack_from('<HBBIII', data, offset)
    if not (0 < vertex_count < 100_000 and triangle_count < 100_000 and 0 < morph_count < 20):
        raise ValueError('Unsupported geometry count')
    offset += 16
    prelit = data[offset:offset + vertex_count * 4] if flags & 8 else None
    if prelit:
        offset += vertex_count * 4
    if tex_count == 0 and flags & 4:
        tex_count = 1
    if tex_count == 0 and flags & 0x80:
        tex_count = 2
    uvs = [struct.unpack_from('<2f', data, offset + n * 8) for n in range(vertex_count)] if tex_count else [(0.5, 0.5)] * vertex_count
    offset += vertex_count * 8 * tex_count
    faces = []
    for n in range(triangle_count):
        v2, v1, material, v3 = struct.unpack_from('<HHHH', data, offset + n * 8)
        if max(v1, v2, v3) >= vertex_count:
            raise ValueError('DFF face index out of range')
        faces.append((v1, v2, v3, material))
    offset += triangle_count * 8
    points = None
    for morph in range(morph_count):
        offset += 16  # bounding sphere
        has_vertices, has_normals = struct.unpack_from('<II', data, offset)
        offset += 8
        if has_vertices:
            current = [struct.unpack_from('<3f', data, offset + n * 12) for n in range(vertex_count)]
            if points is None:
                points = current
            offset += vertex_count * 12
        if has_normals:
            offset += vertex_count * 12
    if offset > info[2] or points is None:
        raise ValueError('Unsupported DFF morph target')
    return points, faces, materials(data, first(parts, 8)), prelit, uvs


def convert(source, destination, pedestrian=False):
    data = source.read_bytes()
    root = list(chunks(data, 0, len(data)))
    clump = first(root, 0x10)
    if clump is None:
        raise ValueError('Not a RenderWare DFF clump')
    parts = children(data, clump)
    frame_chunk = first(parts, 0x0e)
    geometry_chunk = first(parts, 0x1a)
    if not frame_chunk or not geometry_chunk:
        raise ValueError('DFF has no frames or geometry')
    frames = frame_list(data, frame_chunk)
    geometries = [geometry(data, part) for part in children(data, geometry_chunk) if part[0] == 0x0f]
    if not geometries:
        raise ValueError('DFF has no drawable geometry')
    atomics = []
    for item in parts:
        if item[0] != 0x14:
            continue
        info = first(children(data, item), 1)
        if info:
            frame_number, geometry_number = struct.unpack_from('<II', data, info[1])
            if geometry_number < len(geometries) and frame_number < len(frames):
                atomics.append((frame_number, geometry_number))
    if not atomics:
        atomics = [(0, number) for number in range(len(geometries))]
    texture_images = textures(GAME / 'vehicle.txd')
    texture_images.update(textures(source.with_suffix('.txd')))
    texture_names = []
    for _, _, palette, _, _ in geometries:
        for _, name in palette:
            if name and name in texture_images and name not in texture_names:
                texture_names.append(name)
    texture_slots = {name: number + 1 for number, name in enumerate(texture_names)}
    vertices = []
    indices = []
    for frame_number, geometry_number in atomics:
        points, faces, palette, prelit, uvs = geometries[geometry_number]
        # DFF materials belong to faces, so duplicate a vertex when two faces
        # use different material colors.
        cache = {}
        for v1, v2, v3, material in faces:
            color, texture_name = palette[material] if material < len(palette) else (bytes([180, 180, 180, 255]), '')
            for index in (v1, v2, v3):
                key = (index, material)
                if key not in cache:
                    point = transform(points[index], frames, frame_number)
                    if not all(math.isfinite(value) and abs(value) < 1000 for value in point):
                        raise ValueError('Invalid model coordinates')
                    if prelit:
                        lit = prelit[index * 4:index * 4 + 4]
                        tint = bytes(round(color[n] * (0.35 + 0.65 * lit[n] / 255)) for n in range(3)) + bytes([color[3]])
                    else:
                        tint = color
                    cache[key] = len(vertices)
                    vertices.append((point, tint, uvs[index], texture_slots.get(texture_name, 0)))
                indices.append(cache[key])
    if not vertices or len(vertices) > 1_000_000:
        raise ValueError('Empty or oversized DFF model')
    if pedestrian:
        floor = min(point[1] for point, _, _, _ in vertices)
        vertices = [((point[0], -point[2], point[1] - floor), tint, uv, slot)
                    for point, tint, uv, slot in vertices]
    # WRL2 is the world parser's compact, validated binary layout. The model
    # uses a single white atlas cell and vertex colors from the DFF materials.
    result = bytearray(struct.pack('<IIII', 0x324c5257, len(vertices), len(indices), len(texture_names) + 1))
    for point, _, _, _ in vertices:
        result.extend(struct.pack('<3f', *point))
    for _, _, uv, _ in vertices:
        result.extend(struct.pack('<2f', *uv))
    for index in indices:
        result.extend(struct.pack('<I', index))
    for _, tint, _, _ in vertices:
        result.extend(tint)
    for _, _, _, slot in vertices:
        result.extend(struct.pack('<H', slot))
    if len(vertices) % 2:
        result.extend(b'\0\0')
    for _, tint, _, _ in vertices:
        result.extend(tint)
    result.extend(struct.pack('<H', 0) * (len(texture_names) + 1))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(result)
    columns = 8
    cell = 128
    atlas = Image.new('RGBA', (columns * cell, math.ceil((len(texture_names) + 1) / columns) * cell), (255, 255, 255, 255))
    for name, slot in texture_slots.items():
        image = texture_images[name].resize((cell, cell), Image.Resampling.LANCZOS)
        atlas.paste(image, ((slot % columns) * cell, (slot // columns) * cell))
    atlas.save(destination.with_suffix('.png'))
    return len(vertices), len(indices) // 3


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all', action='store_true', help='Convert all archived vehicle and pedestrian models')
    parser.add_argument('models', nargs='*', help='DFF basenames, e.g. taxi bmori')
    args = parser.parse_args()
    selected = set(args.models)
    import extract_client_catalog as catalog
    _, js = catalog.bundle_with('"name":"Manana"')
    vehicles = catalog.json_literal(js, "e.exports=JSON.parse('", "')")
    peds = json.loads((GAME / 'world' / 'peds.json').read_text())['peds']
    ped_names = {item[0].lower() for item in peds}
    if args.all:
        selected.update(item['model'].lower() for item in vehicles)
        selected.update(item[0].lower() for item in peds)
    if not selected:
        selected = {'taxi', 'sultan', 'bmori'}
    written = 0
    for name in sorted(selected):
        source = GAME / f'{name}.dff'
        if not source.is_file():
            continue
        destination = OUTPUT / f'{name}.bin'
        try:
            vertices, faces = convert(source, destination, pedestrian=name in ped_names)
            print(f'{name}: {vertices} vertices, {faces} triangles')
            written += 1
        except (ValueError, struct.error) as error:
            print(f'{name}: skipped ({error})')
    available = {path.stem for path in OUTPUT.glob('*.bin')}
    model_index = {
        'vehicles': {str(item['id']): item['model'].lower() for item in vehicles
                     if item['model'].lower() in available},
        'peds': {str(number): item[0].lower() for number, item in enumerate(peds)
                 if item[0].lower() in available},
    }
    (OUTPUT / 'index.json').write_text(json.dumps(model_index, separators=(',', ':')))
    print(f'Converted {written} local models in {OUTPUT}')


if __name__ == '__main__':
    main()
