#!/usr/bin/env python3
"""Index existing prepared resources; optionally export a portable private package.

No source conversion, ISO extraction, server saves or game engine is run here.
The hash cache avoids re-reading unchanged assets during source-only rebuilds.
All manifests, path mappings and resource bytes remain under local-only.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse
import hashlib
import json
import math
import struct
import os
import shutil
import stat as stat_module
import tempfile

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = {'game/world/index.json', 'game/native/models/index.json',
            'game/native/vehicles.physics.json', 'game/native/foot-animation.json',
            'game/native/models/animations.clips.bin', 'game/native/weapons.json',
            'game/native/seating.json', 'game/native/riders.json'}
EXTENSIONS = {'.bin', '.png', '.jpg', '.jpeg', '.webp', '.json', '.wav', '.ogg', '.mp3', '.txd', '.dff'}


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix='.resource-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as output:
            json.dump(value, output, separators=(',', ':'), sort_keys=True)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def valid_path(name):
    return (0 < len(name.encode()) <= 512 and
            all(c.isascii() and (c.isalnum() or c in '-._/') for c in name) and
            name.startswith(('game/', 'reference/weapons/', 'tools/map/')) and
            all(part not in ('', '.', '..') for part in name.split('/')))


class PreparedAnimationReader:
    """Bounded structural check; activation still requires the Swift verifier.

    Layout/rules follow our NativeSkeletalActor.swift readers. Unknown, changing
    or oversized inputs retain the legacy alternative rather than discard it.
    """
    def __init__(self, path, maximum):
        self.stream = path.open('rb')
        self.before = os.fstat(self.stream.fileno())
        self.remaining = self.before.st_size
        if not 0 < self.remaining <= maximum:
            self.stream.close()
            raise ValueError('Unsupported prepared animation size')

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.stream.close()

    def read(self, count):
        if count < 0 or count > self.remaining:
            raise ValueError('Truncated prepared animation')
        data = self.stream.read(count)
        if len(data) != count:
            raise ValueError('Truncated prepared animation')
        self.remaining -= count
        return data

    def record(self, layout):
        return struct.unpack(layout, self.read(struct.calcsize(layout)))

    def string(self):
        count, = self.record('<H')
        if count > 4096:
            raise ValueError('Unsupported animation name size')
        return self.read(count).decode('utf8')

    def complete(self):
        after = os.fstat(self.stream.fileno())
        stamp = lambda value: (value.st_dev, value.st_ino, value.st_size,
                               value.st_mtime_ns, value.st_ctime_ns)
        return self.remaining == 0 and stamp(self.before) == stamp(after)


def valid_skeletal_library(path):
    try:
        with PreparedAnimationReader(path, 256 * 1024 * 1024) as reader:
            magic, count, aliases, version = reader.record('<4sIII')
            if magic != b'CLP1' or version != 1 or not 0 < count <= 20000 or aliases > 20000:
                return False
            clips = set()
            idle_root = False
            for _ in range(count):
                name = reader.string()
                duration, tracks = reader.record('<fI')
                if not name or name in clips or not math.isfinite(duration) or not 0 <= duration < 3600 or tracks > 512:
                    return False
                clips.add(name)
                bones = set()
                for _ in range(tracks):
                    bone, keys, positioned = reader.record('<iII')
                    if not 0 <= bone <= 10000 or bone in bones or not 0 < keys <= 100000 or positioned > 1:
                        return False
                    bones.add(bone)
                    stride = 32 if positioned else 20
                    if keys * stride > reader.remaining:
                        return False
                    previous = 0.0
                    for first in range(0, keys, 2048):
                        batch = reader.read(min(2048, keys - first) * stride)
                        for key in struct.iter_unpack('<8f' if positioned else '<5f', batch):
                            when, x, y, z, w = key[:5]
                            if not all(math.isfinite(value) for value in key) or when < previous or when < 0 or x*x+y*y+z*z+w*w <= 0.000001:
                                return False
                            previous = when
                if name == 'ped/idle_stance' and 0 in bones:
                    idle_root = True
            mapped = set()
            for _ in range(aliases):
                alias, source, base = reader.string(), reader.string(), reader.string()
                if not alias or alias in mapped or source not in clips or (base and base not in clips):
                    return False
                mapped.add(alias)
            return idle_root and reader.complete()
    except (OSError, ValueError, UnicodeError, struct.error):
        return False


def prepared_mesh_vertex_count(path):
    # Matching filename alone does not bind an SKN1 to its ordered WRL2 mesh.
    # This checks the mesh header/body bound and count. Full geometry, bind pose,
    # textures and actual Metal allocation are checked by the Swift verifier.
    try:
        with path.open('rb') as stream:
            data = stream.read(16)
            if len(data) != 16:
                return None
            magic, vertices, indices, layers = struct.unpack('<4sIII', data)
            if magic != b'WRL2' or not 0 < vertices < 1000000 or not 0 < indices < 3000000 or indices % 3 or not 0 < layers <= 4096:
                return None
            minimum = 16 + vertices * 20 + indices * 4 + vertices * 8 + (vertices + vertices % 2) * 2 + layers * 2
            return vertices if minimum <= os.fstat(stream.fileno()).st_size <= 256 * 1024 * 1024 else None
    except (OSError, ValueError, struct.error):
        return None


def valid_skeletal_pair(path, mesh):
    vertices = prepared_mesh_vertex_count(mesh)
    if vertices is None:
        return False
    try:
        with PreparedAnimationReader(path, 8 * 1024 * 1024) as reader:
            magic, count, frames, bones = reader.record('<4sIII')
            if magic != b'SKN1' or count != vertices or not 0 < count < 100000 or not 0 < frames <= 512 or not 0 < bones <= 64:
                return False
            if reader.remaining != 128 + frames * 72 + bones * 68 + count * 32:
                return False
            if not all(math.isfinite(value) for value in reader.record('<32f')):
                return False
            tags = set()
            for index in range(frames):
                parent, bone, *matrix = reader.record('<ii16f')
                if not -1 <= parent < index or bone < -1 or (bone >= 0 and bone in tags) or not all(math.isfinite(value) for value in matrix):
                    return False
                if bone >= 0:
                    tags.add(bone)
            if 0 not in tags or 1 not in tags:
                return False
            for _ in range(bones):
                frame, *matrix = reader.record('<I16f')
                if frame >= frames or not all(math.isfinite(value) for value in matrix):
                    return False
            for first in range(0, count, 2048):
                batch = reader.read(min(2048, count - first) * 32)
                for vertex in struct.iter_unpack('<3f4B4f', batch):
                    point, ids, weights = vertex[:3], vertex[3:7], vertex[7:]
                    if not all(math.isfinite(value) for value in (*point, *weights)) or any(index >= bones for index in ids) or min(weights) < 0 or abs(sum(weights)-1) >= 0.01:
                        return False
            return reader.complete()
    except (OSError, ValueError, struct.error):
        return False


def candidates(local):
    site = local / 'site'
    result = {}
    for prefix in ['game', 'reference/weapons', 'tools/map']:
        source = site / prefix
        if not source.is_dir():
            continue
        visited = set()
        for folder, directories, names in os.walk(source, followlinks=True):
            real = os.path.realpath(folder)
            if real in visited:
                directories[:] = []
                continue
            visited.add(real)
            directories[:] = sorted(n for n in directories if not n.startswith('.') and n not in {'native-cache', 'node_modules'})
            for name in sorted(names):
                path = Path(folder) / name
                relative = path.relative_to(site).as_posix()
                if name.startswith('.') or name in {'owner.json', 'zgta-resources.json'} or path.suffix.lower() not in EXTENSIONS or not valid_path(relative):
                    continue
                if path.is_file() and path.stat().st_size > 0:
                    result[relative] = path
    # Match the existing server's exact sidecar/working precedence.
    for source in sorted((local / 'native-working/models').glob('*')):
        if source.is_file() and valid_path('game/native/models/' + source.name):
            result['game/native/models/' + source.name] = source
    overrides = {'melee.json': local / 'native/melee.json',
                 'vehicle-coupling.json': local / 'native/vehicle-coupling.json',
                 'vehicle-treads.json': local / 'native/vehicle-treads.json',
                 'original-weapons.json': local / 'original-world-assets/game/native/original-weapons.json',
                 'samp-skins.json': local / 'original-world-assets/game/native/samp-skins.json'}
    for name, source in overrides.items():
        if source.is_file():
            result['game/native/' + name] = source
    # Optional explicitly declared player assembly. Only its thirteen bounded
    # files are indexed; no IMG/CAB is copied or converted by this producer.
    optional_player = local / 'resources-v1/generated/cj-normal-vest-denim-v1'
    if optional_player.exists() or optional_player.is_symlink():
        from tools.assets.prepare_native_cj_profile import candidates as cj_candidates
        result.update(cj_candidates(local))
    # The native renderer uses one shared CLP1 library with SKN1 skeletons.
    # Old per-character baked vertex clips are browser/legacy alternatives,
    # not an additional native dependency. Keep them for legacy-only families.
    library = result.get('game/native/models/animations.clips.bin')
    if library and valid_skeletal_library(library):
        for name in list(result):
            if not name.endswith('.anim.bin'):
                continue
            stem = name[:-len('.anim.bin')]
            skeleton, mesh = result.get(stem + '.skel.bin'), result.get(stem + '.bin')
            if skeleton and mesh and valid_skeletal_pair(skeleton, mesh):
                del result[name]
    return result


def prepare(local, export=None, verify=False):
    output = local / 'resources-v1'
    cache_path = output / 'hash-cache.json'
    cache = json.loads(cache_path.read_text()) if cache_path.is_file() else {}
    resources, blobs, new_cache = [], {}, {}
    hashed = reused = 0
    sources = candidates(local)
    missing = REQUIRED - set(sources)
    if missing:
        raise ValueError('Prepare the existing native runtime first. Missing: ' + ', '.join(sorted(missing)))
    for name, path in sorted(sources.items()):
        stat = path.stat()
        if stat.st_size > 2_147_483_648:
            raise ValueError('Prepared resource exceeds supported per-file size: ' + name)
        stamp = [stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns]
        saved = cache.get(str(path))
        if not verify and saved and saved['stamp'] == stamp:
            digest = saved['sha256']
            reused += 1
        else:
            sha = hashlib.sha256()
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    sha.update(chunk)
            after = path.stat()
            if [after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns] != stamp:
                raise ValueError('Resource changed while indexing: ' + name)
            digest = sha.hexdigest()
            hashed += 1
        new_cache[str(path)] = {'stamp': stamp, 'sha256': digest}
        resources.append({'path': name, 'bytes': stat.st_size, 'sha256': digest, 'required': True})
        blobs.setdefault(digest, {'path': str(path.absolute()), 'bytes': stat.st_size})
    identity = hashlib.sha256(b'zgta-prepared-v1\n')
    for item in resources:
        identity.update((item['path'] + '\0' + str(item['bytes']) + '\0' + item['sha256'] + '\0' + '1\n').encode())
    manifest = {'schema': 1, 'profile': 'zgta-prepared-v1', 'contentID': identity.hexdigest(), 'resources': resources}
    if len(resources) > 200000 or sum(x['bytes'] for x in resources) > 256 * 1024 ** 3:
        raise ValueError('Prepared resource catalogue exceeds the supported bound')
    atomic_json(cache_path, new_cache)
    atomic_json(output / 'catalog.json', {'manifest': manifest, 'files': blobs})
    if export:
        export_catalog(manifest, blobs, export)
    return {'contentID': manifest['contentID'], 'resources': len(resources), 'uniqueBlobs': len(blobs),
            'logicalBytes': sum(x['bytes'] for x in resources), 'physicalBlobBytes': sum(x['bytes'] for x in blobs.values()),
            'hashedFiles': hashed, 'reusedHashReceipts': reused, 'exported': bool(export)}


def export_catalog(manifest, blobs, export):
    """Portable output uses verified content, and commits its manifest last."""
    manifest_path=export/'zgta-resources.json'
    if export.is_symlink() or (export/'blobs').is_symlink() or ((manifest_path.exists()or manifest_path.is_symlink())and not stat_module.S_ISREG(manifest_path.lstat().st_mode)):
        raise ValueError('Portable output must not write through a symlink')
    export.mkdir(parents=True, exist_ok=True)
    target = export / 'blobs'
    target.mkdir(exist_ok=True)
    for digest, item in blobs.items():
        destination = target / digest
        if destination.exists()or destination.is_symlink():
            if not stat_module.S_ISREG(destination.lstat().st_mode):raise ValueError('Portable blob destination is not a regular file')
        if destination.exists():
            before=destination.lstat()
            if before.st_size!=item['bytes']:raise ValueError('Existing export blob has the wrong size: '+digest)
            existing = hashlib.sha256()
            descriptor=os.open(destination,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0))
            with os.fdopen(descriptor,'rb') as stream:
                opened=os.fstat(stream.fileno())
                stamp=lambda value:(value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
                if not stat_module.S_ISREG(opened.st_mode)or stamp(before)!=stamp(opened):raise ValueError('Existing portable blob changed before open')
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    existing.update(chunk)
                if stamp(opened)!=stamp(os.fstat(stream.fileno()))or stamp(opened)!=stamp(destination.lstat()):raise ValueError('Existing portable blob changed during verification')
            if existing.hexdigest() != digest or destination.stat().st_size != item['bytes']:
                raise ValueError('Existing export blob is corrupt: ' + digest)
            continue
        descriptor,name=tempfile.mkstemp(prefix='.'+digest+'-',suffix='.partial',dir=target)
        os.close(descriptor)
        partial=Path(name)
        try:
            source=Path(item['path']).resolve(strict=True);before=source.lstat()
            if not stat_module.S_ISREG(before.st_mode)or before.st_size!=item['bytes']:raise ValueError('Portable source is not the expected regular file')
            flags=os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0)|getattr(os,'O_CLOEXEC',0)
            descriptor=os.open(source,flags)
            with os.fdopen(descriptor,'rb')as incoming,partial.open('wb')as outgoing:
                opened=os.fstat(incoming.fileno())
                stamp=lambda value:(value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
                if not stat_module.S_ISREG(opened.st_mode)or stamp(opened)!=stamp(before):raise ValueError('Portable source changed before open')
                for chunk in iter(lambda:incoming.read(1024*1024),b''):outgoing.write(chunk)
                if stamp(opened)!=stamp(os.fstat(incoming.fileno()))or stamp(opened)!=stamp(source.lstat()):raise ValueError('Portable source changed during export')
            sha = hashlib.sha256()
            with partial.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    sha.update(chunk)
            if sha.hexdigest() != digest or partial.stat().st_size != item['bytes']:
                raise ValueError('Source changed while exporting: ' + digest)
            os.replace(partial, destination)
        finally:
            if partial.exists():partial.unlink()
    atomic_json(export / 'zgta-resources.json', manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-only', type=Path, default=ROOT / 'local-only')
    parser.add_argument('--export', type=Path, help='Optional private portable package destination; no export is needed for normal Mac-hosted development.')
    parser.add_argument('--verify', action='store_true', help='Rehash unchanged source files instead of using stat-bound hash receipts.')
    parser.add_argument('--allow-source-root',type=Path,action='append',help='Explicitly authorize an existing archive directory used by development symlinks. Saved privately; never accepted from a downloaded resource catalogue.')
    parser.add_argument('--base-catalog',type=Path,help='Explicit trusted private prepared catalog for an opt-in stock extension; existing blobs are reused, not rediscovered.')
    parser.add_argument('--stock-config',type=Path,help='Explicit private stock IMG/COL source configuration; never packaged.')
    parser.add_argument('--include-stock-model',type=int,action='append',default=[],help='Include an exact stock object/weapon dependency set; repeat for additional IDs.')
    parser.add_argument('--all-supported',action='store_true',help='Opt in to all available object/weapon metadata candidates, within explicit stock limits; runtime import remains separately verified.')
    parser.add_argument('--stock-max-models',type=int,default=64)
    parser.add_argument('--stock-max-bytes',type=int,default=128*1024*1024)
    args = parser.parse_args()
    try:
        if args.allow_source_root:
            approved=[]
            for entry in args.allow_source_root:
                entry=entry.resolve(strict=True)
                if not entry.is_dir() or entry.parent==entry:
                    raise ValueError('Choose a specific existing game-resource directory')
                approved.append(str(entry))
            atomic_json(args.local_only/'resource-source-roots.json',sorted(set(approved)))
        if args.include_stock_model or args.all_supported or args.base_catalog or args.stock_config:
            if not args.base_catalog or not args.stock_config or not (args.include_stock_model or args.all_supported):
                raise ValueError('Stock extension requires --base-catalog, --stock-config and explicit model selection')
            from tools.assets.prepare_native_stock_package import extend
            result=extend(args.base_catalog,args.local_only.absolute(),args.stock_config,args.include_stock_model,
                          all_supported=args.all_supported,maximum_models=args.stock_max_models,
                          maximum_bytes=args.stock_max_bytes,export=args.export)
        else:result=prepare(args.local_only.absolute(), args.export, args.verify)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error))


if __name__ == '__main__':
    main()
