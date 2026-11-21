#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Prepare exact HUD weapon sprites from owner-local weapon definitions/TXDs.

No discovery, network access or game data in source. Original resolution and
RGBA are preserved. The new output directory stays under local-only; existing
archives, resources and installed catalogues are never overwritten.
"""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
import argparse
import hashlib
import io
import json
import os
import re
import shutil
import stat
import struct
import tempfile
from tools.assets.prepare_native_models import chunks, children, first, textures

def digest(data):
    return hashlib.sha256(data).hexdigest()

def read(path, maximum):
    path = Path(path)
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= maximum:
        raise ValueError('A bounded regular source file is required')
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(descriptor, 'rb') as stream:
        opened = os.fstat(stream.fileno())
        stamp = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
        if stamp(opened) != stamp(before):
            raise ValueError('Source changed before acquisition')
        data = stream.read(maximum + 1)
        if len(data) != before.st_size or stamp(os.fstat(stream.fileno())) != stamp(before) or stamp(path.lstat()) != stamp(before):
            raise ValueError('Source changed while reading')
    return data

def no_symlink_parents(path):
    for item in [path, *path.parents]:
        if item.is_symlink():
            raise ValueError('Generated resources must not traverse symlinks')

def validate_txd(data):
    roots = list(chunks(data, 0, len(data)))
    if len(roots) != 1 or roots[0][0] != 22:
        raise ValueError('One exact RenderWare texture dictionary is required')
    count = pixels = 0
    names = set()
    directory = first(children(data, roots[0]), 1)
    if directory is None or directory[2] - directory[1] < 4:
        raise ValueError('Texture dictionary has no declared count')
    declared = struct.unpack_from('<H', data, directory[1])[0]
    for item in children(data, roots[0]):
        if item[0] != 21:
            continue
        count += 1
        info = first(children(data, item), 1)
        if count > 256 or info is None or info[2] - info[1] < 92:
            raise ValueError('Invalid native texture directory')
        at = info[1]
        name = data[at + 8:at + 40].split(b'\0', 1)[0].decode('ascii').lower()
        if not name or name in names:
            raise ValueError('Empty or ambiguous texture identity')
        names.add(name)
        width, height = struct.unpack_from('<HH', data, at + 80)
        size = struct.unpack_from('<I', data, at + 88)[0]
        pixels += width * height
        if not 0 < width <= 4096 or not 0 < height <= 4096 or pixels > 16 * 1024 * 1024 or size > info[2] - at - 92:
            raise ValueError('Texture exceeds declared decode bounds')
    if not count or count != declared:
        raise ValueError('Texture dictionary count differs from its native entries')

def source_plan(catalog, game):
    definitions_data = read(Path(catalog).resolve(strict=True), 4 * 1024 * 1024)
    game = Path(game).resolve(strict=True)
    definitions = json.loads(definitions_data).get('definitions')
    if not isinstance(definitions, list) or not 1 <= len(definitions) <= 128:
        raise ValueError('Bounded weapon definitions are required')
    plan, seen = [], set()
    for row in definitions:
        if not isinstance(row, dict) or row.get('icon') is not True:
            continue
        weapon, model = row.get('id'), row.get('modelName')
        if type(weapon) is not int or not 0 <= weapon <= 46 or weapon in seen:
            raise ValueError('Invalid or duplicate HUD weapon identity')
        seen.add(weapon)
        if weapon == 0:
            source, sprite = Path(game) / 'hud.txd', 'fist'
        elif isinstance(model, str) and re.fullmatch('[a-z0-9_]{1,64}', model):
            source, sprite = Path(game) / (model + '.txd'), model + 'icon'
        else:
            raise ValueError('Weapon has no exact safe model identity')
        source = source.resolve(strict=True)
        plan.append((weapon, source, sprite))
    if not plan:
        raise ValueError('No declared HUD icons were prepared')
    return definitions_data, plan

def output_path(output, private_root):
    output = Path(os.path.abspath(output))
    private_root = Path(os.path.abspath(private_root))
    no_symlink_parents(output)
    if not output.is_relative_to(private_root) or output == private_root:
        raise ValueError('A directory inside local-only is required')
    return output

def prepare(catalog, game, output, private_root):
    output = output_path(output, private_root)
    if output.exists():
        raise ValueError('A new directory inside local-only is required')
    definitions_data, plan = source_plan(catalog, game)
    rows, images = [], {}
    for weapon, source, sprite in plan:
        data = read(source, 32 * 1024 * 1024)
        validate_txd(data)
        # The shared decoder reads the same regular file. Reject replacement
        # before accepting any pixels or publishing the staged directory.
        image = textures(source).get(sprite.lower())
        if read(source, 32 * 1024 * 1024) != data or image is None:
            raise ValueError('Exact original weapon icon is absent or source changed')
        encoded = io.BytesIO()
        image.save(encoded, format='PNG')
        png = encoded.getvalue()
        file = str(weapon) + '.png'
        images[file] = png
        rows.append(dict(id=weapon, path=f'reference/weapons/{file}', file=file,
            width=image.width, height=image.height, bytes=len(png), sha256=digest(png),
            source=dict(file=source.name, sha256=digest(data), texture=sprite)))
    if not rows:
        raise ValueError('No declared HUD icons were prepared')
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.weapon-icons-', dir=output.parent))
    try:
        for name, data in images.items():
            (stage / name).write_bytes(data)
            (stage / name).chmod(0o600)
        manifest = dict(version=1, icons=sorted(rows, key=lambda row: row['id']),
            definitionsSHA256=digest(definitions_data), originalResolution=True)
        (stage / 'manifest.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
        (stage / 'manifest.json').chmod(0o600)
        # rename cannot silently replace a populated directory; recheck the
        # selected destination before publishing the complete staged result.
        if output.exists() or output.is_symlink():
            raise ValueError('Output appeared during preparation')
        stage.rename(output)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return manifest

def validated_prepared(base):
    base = Path(base)
    no_symlink_parents(base)
    document = json.loads(read(base / 'manifest.json', 128 * 1024))
    rows = document.get('icons')
    if document.get('version') != 1 or not isinstance(rows, list) or not 1 <= len(rows) <= 47:
        raise ValueError('Invalid prepared weapon-icon catalogue')
    result = {}
    for row in rows:
        weapon = row.get('id')
        if type(weapon) is not int or not 0 <= weapon <= 46:
            raise ValueError('Invalid prepared weapon icon ID')
        name = str(weapon) + '.png'
        logical = 'reference/weapons/' + name
        if row.get('file') != name or row.get('path') != logical or logical in result:
            raise ValueError('Invalid or duplicate prepared weapon icon path')
        data = read(base / name, 4 * 1024 * 1024)
        if len(data) != row.get('bytes') or digest(data) != row.get('sha256'):
            raise ValueError('Prepared weapon icon identity changed')
        if len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
            raise ValueError('Prepared weapon icon is not a PNG')
        width, height = struct.unpack_from('>II', data, 16)
        if not 0 < width <= 4096 or not 0 < height <= 4096 or width != row.get('width') or height != row.get('height'):
            raise ValueError('Prepared weapon icon dimensions changed')
        result[logical] = base / name
    return document, result

def candidates(local):
    return validated_prepared(Path(local) / 'native-weapon-icons')[1]

def prepare_if_needed(catalog, game, output, private_root):
    """Reuse only an intact generation bound to every current source input.

    A changed/corrupt existing generation is an explicit failure. It is never
    overwritten, silently reused, or decoded into an unrequested replacement.
    """
    output = output_path(output, private_root)
    if not output.exists():
        return prepare(catalog, game, output, private_root), False
    document, _ = validated_prepared(output)
    definitions_data, plan = source_plan(catalog, game)
    if document.get('originalResolution') is not True or document.get('definitionsSHA256') != digest(definitions_data):
        raise ValueError('Prepared weapon-icon inputs changed; preserve the old output separately and prepare a new directory')
    rows = {row['id']: row for row in document['icons']}
    if set(rows) != {weapon for weapon, _, _ in plan}:
        raise ValueError('Prepared weapon-icon identities differ from current definitions')
    for weapon, source, sprite in plan:
        expected = dict(file=source.name, sha256=digest(read(source, 32 * 1024 * 1024)), texture=sprite)
        if rows[weapon].get('source') != expected:
            raise ValueError('Prepared weapon-icon source changed; preserve the old output separately and prepare a new directory')
    if read(Path(catalog).resolve(strict=True), 4 * 1024 * 1024) != definitions_data:
        raise ValueError('Weapon definitions changed during reuse verification')
    return document, True

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, required=True)
    parser.add_argument('--game', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'local-only/native-weapon-icons')
    parser.add_argument('--if-needed', action='store_true', help='Verify and reuse an unchanged generation; reject changed or corrupt existing output')
    args = parser.parse_args()
    if args.if_needed:
        result, reused = prepare_if_needed(args.catalog, args.game, args.output, ROOT / 'local-only')
    else:
        result, reused = prepare(args.catalog, args.game, args.output, ROOT / 'local-only'), False
    action = 'Verified existing' if reused else 'Prepared'
    print(f'{action} {len(result["icons"])} original-resolution HUD weapon icons in local-only')

if __name__ == '__main__':
    main()
