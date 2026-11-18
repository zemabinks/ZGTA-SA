#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Explicit, private native-detail pedestrian families and prepared extension.

Build converts only hash-pinned selected own DFF/TXD inputs into a fresh output.
Extend merges a complete family into a trusted prepared catalogue; it never
discovers sources, changes source-root approvals, starts a service or seeds an
app cache. Original and derived resources must remain outside the source tree.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import math
import os
import re
import shutil
import stat
import struct
import tempfile

import prepare_native_models as converter
from prepare_native_resource_package import valid_skeletal_pair

PREFIX = 'game/native/models/ped-atlas-v1/'
INDEX = 'game/native/models/index.json'
FORMAT = 'zgta-ped-atlas-family-v1'
OVERLAY_FORMAT = 'zgta-ped-atlas-overlay-v1'
SHA = re.compile(r'[0-9a-f]{64}\Z')
MODEL = re.compile(r'[a-z0-9_]{1,64}\Z')
SUFFIX = {'mesh': '.bin', 'atlas': '.png', 'layout': '.atlas.json',
          'skeleton': '.skel.bin', 'hand': '.hand.bin', 'parts': '.parts.json'}
REQUIRED = {'mesh', 'atlas', 'layout', 'skeleton'}
LIMIT = {'dff': 4*1024*1024, 'txd': 4*1024*1024, 'mesh': 4*1024*1024,
         'atlas': 2*1024*1024, 'layout': 65536, 'skeleton': 4*1024*1024,
         'hand': 1024*1024, 'parts': 256*1024}
MAX_MODELS = 32
MAX_BYTES = 32*1024*1024


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def integer(value, low, high):
    return type(value) is int and low <= value <= high


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key')
        result[key] = value
    return result


def decode_json(data):
    return json.loads(data, object_pairs_hook=no_duplicates)


def no_links(path):
    path = Path(path).absolute()
    if '..' in path.parts:
        raise ValueError('Selected path must not contain parent traversal')
    for part in [*reversed(path.parents), path]:
        if part.is_symlink():
            raise ValueError('Selected path must not traverse symlinks: ' + str(part))
    return path


def regular_bytes(path, maximum):
    path = no_links(path)
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= maximum:
        raise ValueError('Selected source is not a bounded regular file: ' + str(path))
    stamp = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
    fd = os.open(path, flags)
    with os.fdopen(fd, 'rb') as source:
        opened = os.fstat(source.fileno())
        if not stat.S_ISREG(opened.st_mode) or stamp(opened) != stamp(before):
            raise ValueError('Selected source changed before open')
        data = source.read(maximum + 1)
        if (len(data) != opened.st_size or stamp(opened) != stamp(os.fstat(source.fileno()))
                or stamp(opened) != stamp(path.lstat())):
            raise ValueError('Selected source changed during read')
    return data


def read_spec(spec, role):
    if (not isinstance(spec, dict) or set(spec) != {'path', 'bytes', 'sha256'}
            or not isinstance(spec['path'], str) or not Path(spec['path']).is_absolute()
            or not integer(spec['bytes'], 1, LIMIT[role])
            or not isinstance(spec['sha256'], str) or not SHA.fullmatch(spec['sha256'])):
        raise ValueError('Explicit size/SHA256-pinned source required for ' + role)
    data = regular_bytes(spec['path'], LIMIT[role])
    if len(data) != spec['bytes'] or digest(data) != spec['sha256']:
        raise ValueError('Selected source size/SHA256 mismatch: ' + role)
    return data


def fresh_private(path):
    path = no_links(path)
    if 'local-only' not in path.parts or path.exists():
        raise ValueError('Choose a fresh regular output under an explicit local-only directory')
    path.parent.mkdir(parents=True, exist_ok=True)
    no_links(path.parent)
    return path


def preflight_txd(data):
    """Bound image allocations before the existing selected-input decoder runs."""
    roots = list(converter.chunks(data, 0, len(data)))
    root = converter.first(roots, 0x16)
    if root is None:
        raise ValueError('Selected TXD has no dictionary')
    total = count = 0
    names = set()
    for native in converter.children(data, root):
        if native[0] != 0x15:
            continue
        info = converter.first(converter.children(data, native), 1)
        if info is None or info[2] - info[1] < 92:
            raise ValueError('Selected TXD native header is truncated')
        at = info[1]
        name = data[at+8:at+40].split(b'\0')[0].decode('ascii').lower()
        platform, = struct.unpack_from('<I', data, at)
        width, height = struct.unpack_from('<HH', data, at+80)
        size, = struct.unpack_from('<I', data, at+88)
        code = data[at+76:at+80]
        if (platform != 9 or not name or name in names or not 0 < width <= 1024
                or not 0 < height <= 1024 or at+92+size > info[2]
                or code not in (b'DXT1', b'DXT3', b'DXT5', struct.pack('<I', 21), struct.pack('<I', 22))):
            raise ValueError('Unsupported selected TXD image')
        total += width*height*4
        count += 1
        names.add(name)
        if total > 512*1024 or count > 32:
            raise ValueError('Selected TXD exceeds decoded pixel budget')
    return names


def validate_layout(layout, mesh, png):
    if (not isinstance(layout, dict) or layout.get('schema') != 1 or layout.get('layout') != 'ped-tight-native-v1'
            or layout.get('sampling') != 'legacy-inset-fract-linear-no-mips'):
        raise ValueError('Unknown pedestrian layout')
    if digest(mesh) != layout.get('meshSHA256') or digest(png) != layout.get('atlasSHA256'):
        raise ValueError('Layout binary/atlas family mismatch')
    if len(mesh) < 16 or mesh[:4] != b'WRL2':
        raise ValueError('Layout mesh header')
    count = struct.unpack_from('<I', mesh, 12)[0]
    if len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Layout PNG header')
    size = list(struct.unpack_from('>II', png, 16))
    cell, columns, layers = layout.get('cell'), layout.get('columns'), layout.get('layers')
    if (not isinstance(cell, list) or len(cell) != 2 or not all(integer(v, 1, 4096) for v in cell)
            or not integer(columns, 1, 8) or size != layout.get('atlas')
            or columns*cell[0] != size[0] or not isinstance(layers, list)
            or not 1 <= len(layers) == count <= 33
            or math.ceil(count/columns)*cell[1] != size[1]
            or size[0]*size[1]*4 != layout.get('logicalRGBA8Bytes')
            or not size[0]*size[1]*4 <= 512*1024
            or layout.get('maximumRGBA8Bytes') != 512*1024):
        raise ValueError('Layout dimensions/layer/pixel budget')
    texture_names = set()
    for i, row in enumerate(layers):
        rect = row.get('rect') if isinstance(row, dict) else None
        if (not isinstance(rect, list) or len(rect) != 4 or not all(type(v) is int for v in rect)
                or row.get('slot') != i or rect[:2] != [(i % columns)*cell[0], (i//columns)*cell[1]]
                or not 0 < rect[2] <= cell[0] or not 0 < rect[3] <= cell[1]):
            raise ValueError('Layout content rectangle')
        name = row.get('texture')
        if i == 0:
            if name is not None or rect[2:] != cell:
                raise ValueError('Layout white slot')
        elif not isinstance(name, str) or not name or not name.isascii() or name in texture_names:
            raise ValueError('Layout texture slot name')
        else:
            texture_names.add(name)
    if not isinstance(layout.get('sourceDFFSHA256'), str) or not SHA.fullmatch(layout['sourceDFFSHA256']):
        raise ValueError('Missing selected DFF identity')
    txd = layout.get('sourceTXDSHA256')
    if txd is not None and (not isinstance(txd, str) or not SHA.fullmatch(txd)):
        raise ValueError('Invalid selected TXD identity')
    from PIL import Image
    with Image.open(io.BytesIO(png)) as image:
        if image.mode != 'RGBA' or list(image.size) != size:
            raise ValueError('Atlas must decode to its declared RGBA extent')
        image.verify()


def source_identity(model, layout):
    return digest(canonical({'model': model, 'sourceDFFSHA256': layout['sourceDFFSHA256'],
                             'sourceTXDSHA256': layout.get('sourceTXDSHA256')}))


def validate_optional(values, mesh):
    if 'parts' in values:
        parts = decode_json(values['parts'])
        records = parts.get('parts') if isinstance(parts, dict) else None
        indices = struct.unpack_from('<I', mesh, 8)[0]
        if not isinstance(records, list) or not 1 <= len(records) <= 512:
            raise ValueError('Invalid advertised parts')
        for row in records:
            if (not isinstance(row, dict) or not isinstance(row.get('name'), str)
                    or not integer(row.get('start'), 0, indices)
                    or not integer(row.get('count'), 0, indices)
                    or row['start']+row['count'] > indices):
                raise ValueError('Invalid advertised part draw range')
    if 'hand' in values:
        data = values['hand']
        if len(data) < 16 or data[:4] != b'HND1':
            raise ValueError('Invalid advertised hand header')
        count, fps = struct.unpack_from('<II', data, 4)
        if not 1 <= count <= 128 or not 1 <= fps <= 120:
            raise ValueError('Invalid advertised hand counts')
        offset, names = 16, set()
        for _ in range(count):
            if offset+20 > len(data):
                raise ValueError('Truncated advertised hand clip')
            name = data[offset:offset+16].split(b'\0')[0].decode('ascii')
            frames, = struct.unpack_from('<I', data, offset+16)
            offset += 20
            if not name or name in names or not 1 <= frames <= 1000 or offset+frames*64 > len(data):
                raise ValueError('Invalid advertised hand clip')
            names.add(name)
            for frame in struct.iter_unpack('<16f', data[offset:offset+frames*64]):
                if not all(math.isfinite(value) for value in frame):
                    raise ValueError('Nonfinite advertised hand matrix')
            offset += frames*64
        if offset != len(data):
            raise ValueError('Trailing advertised hand bytes')


def resource(model, role, data):
    sha = digest(data)
    return {'path': PREFIX+sha+'/'+model+SUFFIX[role], 'bytes': len(data), 'sha256': sha}


def build(selection, output):
    if (not isinstance(selection, dict) or selection.get('schema') != 1
            or not isinstance(selection.get('models'), list) or not 1 <= len(selection['models']) <= MAX_MODELS
            or not all(isinstance(row, dict) for row in selection['models'])):
        raise ValueError('Explicit bounded pedestrian selection required')
    output = fresh_private(output)
    stage = Path(tempfile.mkdtemp(prefix='.ped-atlas-partial-', dir=output.parent))
    rows, model_urls, provenance = {}, {}, []
    total = 0
    try:
        for selected in selection['models']:
            model = selected.get('model', '')
            specs = selected.get('sources')
            if (not isinstance(model, str) or not MODEL.fullmatch(model) or model == 'null' or model in model_urls
                    or not isinstance(specs, dict) or not {'dff', 'txd', 'mesh', 'skeleton'} <= set(specs)
                    or set(specs)-{'dff', 'txd', 'mesh', 'skeleton', 'hand', 'parts'}):
                raise ValueError('Invalid/duplicate selected model or source roles')
            data = {role: read_spec(spec, role) for role, spec in specs.items()}
            if Path(specs['dff']['path']).name != model+'.dff' or Path(specs['txd']['path']).name != model+'.txd':
                raise ValueError('Selected source basename must match the model')
            preflight_txd(data['txd'])
            work = stage/'.work'/model
            work.mkdir(parents=True)
            source = work/(model+'.dff')
            source.write_bytes(data['dff'])
            source.with_suffix('.txd').write_bytes(data['txd'])
            destination = work/'converted.bin'
            converter.convert(source, destination, pedestrian=True, ped_atlas_layout='tight-native')
            if destination.read_bytes() != data['mesh']:
                raise ValueError('Selected existing mesh/SKN ordering differs from current export: '+model)
            if 'parts' in data and destination.with_suffix('.parts.json').read_bytes() != data['parts']:
                raise ValueError('Selected existing parts differ from current export: '+model)
            skin = work/'existing.skel.bin'
            skin.write_bytes(data['skeleton'])
            if not valid_skeletal_pair(skin, destination):
                raise ValueError('Selected skeleton is not a valid exact mesh pair: '+model)
            generated = {role: data[role] for role in ['mesh', 'skeleton', 'hand', 'parts'] if role in data}
            generated['atlas'] = destination.with_suffix('.png').read_bytes()
            generated['layout'] = destination.with_suffix('.atlas.json').read_bytes()
            layout = decode_json(generated['layout'])
            validate_layout(layout, generated['mesh'], generated['atlas'])
            validate_optional(generated, generated['mesh'])
            if layout['sourceDFFSHA256'] != digest(data['dff']) or layout['sourceTXDSHA256'] != digest(data['txd']):
                raise ValueError('Generated source identity mismatch')
            resources = {role: resource(model, role, value) for role, value in generated.items()}
            family = {'schema': 1, 'format': FORMAT, 'model': model,
                      'sourceIdentity': source_identity(model, layout), 'resources': resources}
            family_data = canonical(family)+b'\n'
            family_record = {'path': PREFIX+digest(family_data)+'/'+model+'.json',
                             'bytes': len(family_data), 'sha256': digest(family_data)}
            for record, value in [(resources[role], value) for role, value in generated.items()]+[(family_record, family_data)]:
                path = stage/'files'/record['path']
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(value)
                rows[record['path']] = record
                total += len(value)
            if total > MAX_BYTES:
                raise ValueError('Selected pedestrian graph exceeds the output budget')
            model_urls[model] = family_record['path']
            provenance.append({'model': model, 'sources': specs, 'sourceIdentity': family['sourceIdentity'],
                               'meshUnchanged': True, 'skeletonUnchanged': True,
                               'partsUnchanged': 'parts' in data, 'handUnchanged': 'hand' in data,
                               'atlasRGBA8Bytes': layout['logicalRGBA8Bytes']})
        shutil.rmtree(stage/'.work')
        overlay = {'schema': 1, 'format': OVERLAY_FORMAT, 'models': model_urls,
                   'resources': [rows[name] for name in sorted(rows)]}
        (stage/'overlay.json').write_bytes(canonical(overlay)+b'\n')
        (stage/'provenance.json').write_bytes(canonical({'schema': 1, 'models': provenance})+b'\n')
        validate_overlay(stage)
        os.rename(stage, output)
        return {'models': len(model_urls), 'resources': len(rows), 'logicalBytes': total,
                'output': str(output), 'overlaySHA256': digest(canonical(overlay)+b'\n')}
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def validate_overlay(directory):
    directory = no_links(directory)
    overlay = decode_json(regular_bytes(directory/'overlay.json', 256*1024))
    if not isinstance(overlay, dict):
        raise ValueError('Invalid pedestrian overlay object')
    urls, records = overlay.get('models'), overlay.get('resources')
    if (overlay.get('schema') != 1 or overlay.get('format') != OVERLAY_FORMAT
            or not isinstance(urls, dict) or not 1 <= len(urls) <= MAX_MODELS
            or not isinstance(records, list) or not 1 <= len(records) <= MAX_MODELS*7):
        raise ValueError('Invalid pedestrian overlay')
    files, content = {}, {}
    total = 0
    for row in records:
        if (not isinstance(row, dict) or set(row) != {'path', 'bytes', 'sha256'}
                or not isinstance(row['path'], str) or not row['path'].startswith(PREFIX)
                or not integer(row['bytes'], 1, 4*1024*1024)
                or not isinstance(row['sha256'], str) or not SHA.fullmatch(row['sha256'])
                or row['path'] in files):
            raise ValueError('Invalid overlay resource')
        tail = row['path'][len(PREFIX):].split('/')
        if len(tail) != 2 or tail[0] != row['sha256'] or not re.fullmatch(r'[a-z0-9_.]{1,96}', tail[1]):
            raise ValueError('Invalid immutable overlay path')
        path = directory/'files'/row['path']
        value = regular_bytes(path, 4*1024*1024)
        if len(value) != row['bytes'] or digest(value) != row['sha256']:
            raise ValueError('Overlay resource size/SHA256 mismatch')
        files[row['path']] = path
        content[row['path']] = value
        total += len(value)
    if total > MAX_BYTES:
        raise ValueError('Overlay graph byte budget')
    used = set()
    for model, url in urls.items():
        if not isinstance(model, str) or not MODEL.fullmatch(model) or model == 'null' or not isinstance(url, str) or url not in content:
            raise ValueError('Invalid overlay model selection')
        if len(content[url]) > 65536:
            raise ValueError('Oversized family descriptor')
        family = decode_json(content[url])
        if (not isinstance(family, dict) or family.get('schema') != 1 or family.get('format') != FORMAT or family.get('model') != model
                or url != PREFIX+digest(content[url])+'/'+model+'.json'):
            raise ValueError('Invalid pinned family identity')
        resources = family.get('resources')
        if not isinstance(resources, dict) or not REQUIRED <= set(resources) or set(resources)-set(SUFFIX):
            raise ValueError('Incomplete pedestrian family')
        values = {}
        for role, row in resources.items():
            if (not isinstance(row, dict) or row.get('path') not in content
                    or row != resource(model, role, content[row['path']])):
                raise ValueError('Invalid complete family dependency')
            values[role] = content[row['path']]
            if len(values[role]) > LIMIT[role]:
                raise ValueError('Family role exceeds its byte bound')
            used.add(row['path'])
        layout = decode_json(values['layout'])
        validate_layout(layout, values['mesh'], values['atlas'])
        validate_optional(values, values['mesh'])
        if family.get('sourceIdentity') != source_identity(model, layout):
            raise ValueError('Family source identity mismatch')
        if not valid_skeletal_pair(files[resources['skeleton']['path']], files[resources['mesh']['path']]):
            raise ValueError('Family skeleton/mesh mismatch')
        used.add(url)
    if used != set(content):
        raise ValueError('Unadvertised resources in overlay')
    return overlay, files


def extend(base_catalog, overlay_directory, local):
    """Normal prepared manifest extension, using only explicitly selected inputs."""
    from prepare_native_stock_package import validate_base, manifest_identity
    from prepare_native_resource_package import atomic_json
    base_catalog = Path(base_catalog).resolve(strict=True)
    base = decode_json(regular_bytes(base_catalog, 96*1024*1024))
    if not isinstance(base, dict):
        raise ValueError('Invalid prepared base object')
    rows, files = validate_base(base)
    overlay, selected = validate_overlay(overlay_directory)
    old_index = next(row for row in rows if row['path'] == INDEX)
    index_file = Path(files[old_index['sha256']]['path']).resolve(strict=True)
    index_bytes = regular_bytes(index_file, 1024*1024)
    if len(index_bytes) != old_index['bytes'] or digest(index_bytes) != old_index['sha256']:
        raise ValueError('Base model index changed')
    index = decode_json(index_bytes)
    if (not isinstance(index, dict) or any(not isinstance(value, dict) or any(not isinstance(k, str)
            or not isinstance(v, str) for k, v in value.items()) for value in index.values())):
        raise ValueError('Preserve the existing all-string model index schema')
    if not set(overlay['models']) <= set(index.get('peds', {}).values()):
        raise ValueError('Selected family is not an existing ordinary pedestrian model')
    index.setdefault('pedAtlasV1', {}).update(overlay['models'])
    index_bytes = canonical(index)+b'\n'
    local = no_links(local)
    if 'local-only' not in local.parts or not local.is_dir():
        raise ValueError('Choose an existing regular private local-only directory')
    destination = local/'resources-v1/catalog.json'
    if destination.exists() or destination.is_symlink():
        raise ValueError('Choose a fresh prepared destination; the existing catalogue is preserved')
    transaction = digest(canonical({'baseContentID': base['manifest']['contentID'],
                                    'overlaySHA256': digest(canonical(overlay)+b'\n')}))
    output = fresh_private(local/'resources-v1/generated/ped-atlas-v1'/transaction)
    stage = Path(tempfile.mkdtemp(prefix='.ped-extension-', dir=output.parent))
    committed = False
    try:
        for name, source in selected.items():
            target = stage/'files'/name
            target.parent.mkdir(parents=True, exist_ok=True)
            row = next(row for row in overlay['resources'] if row['path'] == name)
            value = regular_bytes(source, 4*1024*1024)
            if len(value) != row['bytes'] or digest(value) != row['sha256']:
                raise ValueError('Overlay changed while preparing extension')
            target.write_bytes(value)
        (stage/'index.json').write_bytes(index_bytes)
        os.rename(stage, output)
        committed = True
        by_path = {row['path']: row for row in rows}
        for row in overlay['resources']:
            by_path[row['path']] = {**row, 'required': True}
            files.setdefault(row['sha256'], {'path': str(output/'files'/row['path']), 'bytes': row['bytes']})
        by_path[INDEX] = {'path': INDEX, 'bytes': len(index_bytes), 'sha256': digest(index_bytes), 'required': True}
        files[digest(index_bytes)] = {'path': str(output/'index.json'), 'bytes': len(index_bytes)}
        rows = [by_path[name] for name in sorted(by_path)]
        if len(rows) > 200000 or sum(row['bytes'] for row in rows) > 256*1024**3:
            raise ValueError('Prepared graph exceeds normal resource limits')
        manifest = {'schema': 1, 'profile': 'zgta-prepared-v1',
                    'contentID': manifest_identity(rows), 'resources': rows}
        validate_base({'manifest': manifest, 'files': files})
        atomic_json(destination, {'manifest': manifest, 'files': files})
        return {'contentID': manifest['contentID'], 'resources': len(rows), 'models': len(overlay['models']),
                'generatedDirectory': str(output), 'catalog': str(destination),
                'baseCatalogueUnchanged': True, 'sourceRootApprovalsChanged': False}
    finally:
        if stage.exists():
            shutil.rmtree(stage)
        if committed and not destination.exists():
            shutil.rmtree(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build_parser = commands.add_parser('build', help='Convert only explicit hash-pinned selected pedestrian inputs')
    build_parser.add_argument('--selection', type=Path, required=True)
    build_parser.add_argument('--output', type=Path, required=True)
    extend_parser = commands.add_parser('extend', help='Merge a validated family into a fresh normal prepared catalogue')
    extend_parser.add_argument('--base-catalog', type=Path, required=True)
    extend_parser.add_argument('--overlay', type=Path, required=True)
    extend_parser.add_argument('--local-only', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'build':
            result = build(decode_json(regular_bytes(args.selection, 256*1024)), args.output)
        else:
            result = extend(args.base_catalog, args.overlay, args.local_only)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, KeyError, TypeError, struct.error) as error:
        raise SystemExit(str(error))


if __name__ == '__main__':
    main()
