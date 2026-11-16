#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Catalog exact authored COL records from owner-supplied VER2 IMG archives.

No geometry is synthesized. Model names come from an explicit request (normally
the exact active IDE name). Distinct same-name records remain ambiguous; identical
bytes are aliases. Original records and generated metadata stay under local-only.
This is a bounded container/header reader, not a replacement for the native COL
geometry validator. It never reads or modifies any game installation by default.
"""
import argparse
import binascii
import hashlib
import json
from pathlib import Path
import re
import struct

NAME = re.compile(r'[A-Za-z0-9_#+.()\-]{1,128}\Z')
VERSIONS = {b'COLL': 1, b'COL2': 2, b'COL3': 3}
MAX_ARCHIVE = 4 * 1024**3
MAX_ENTRIES = 100_000
MAX_COLLECTION = 32 * 1024**2
MAX_RECORDS = 100_000
MAX_SELECTED = 64 * 1024**2


def canonical(value):
    if not NAME.fullmatch(value) or '..' in value or value in ('.', '..'):
        raise ValueError('Invalid exact model name')
    return value.lower()


def scan(archives, requested, loose_collections=()):
    """Read bounded directory/COL ranges. Return metadata and selected raw bytes."""
    requested = {canonical(value) for value in requested}
    if not requested or len(requested) > 30_000 or not 1 <= len(archives) <= 16:
        raise ValueError('Archive/request count limit')
    assets = {name: {} for name in requested}
    sources = []
    record_count = collection_count = selected_bytes = 0
    versions = {}
    archive_names = set()
    for raw_path in archives:
        path = Path(raw_path).resolve()
        if not path.is_file() or path.stat().st_size > MAX_ARCHIVE:
            raise ValueError('Missing or excessive IMG archive')
        if path.name.lower() in archive_names:
            raise ValueError('Ambiguous IMG archive basename')
        archive_names.add(path.name.lower())
        before = path.stat()
        with path.open('rb') as stream:
            header = stream.read(8)
            if len(header) != 8 or header[:4] != b'VER2':
                raise ValueError('Only PC VER2 IMG archives are supported')
            count = struct.unpack_from('<I', header, 4)[0]
            if count > MAX_ENTRIES or 8 + count * 32 > before.st_size:
                raise ValueError('IMG directory limit/truncation')
            directory = stream.read(count * 32)
            source = {'archive': path.name, 'bytes': before.st_size,
                      'directorySHA256': hashlib.sha256(header + directory).hexdigest(),
                      'entries': count}
            sources.append(source)
            ranges = []
            for index in range(count):
                sector, sectors, packed = struct.unpack_from('<IHH', directory, index * 32)
                name_bytes = directory[index * 32 + 8:index * 32 + 32]
                name = name_bytes.split(b'\0', 1)[0].decode('ascii', errors='strict')
                if not name or '/' in name or '\\' in name or '..' in name:
                    raise ValueError('Invalid IMG entry name')
                offset, size = sector * 2048, sectors * 2048
                if offset < 8 + count * 32 or size <= 0 or offset + size > before.st_size:
                    raise ValueError('IMG allocation outside archive')
                if not name.lower().endswith('.col'):
                    continue
                if packed:
                    raise ValueError('Compressed COL IMG entry is unsupported')
                if size > MAX_COLLECTION:
                    raise ValueError('COL collection byte limit')
                ranges.append((offset, size, name))
            # Aliased/overlapping allocations could hide contradictory records.
            ordered = sorted(ranges)
            if any(a[0] + a[1] > b[0] for a, b in zip(ordered, ordered[1:])):
                raise ValueError('Overlapping COL IMG allocations')
            for offset, size, collection in ranges:
                collection_count += 1
                stream.seek(offset)
                data = stream.read(size)
                if len(data) != size:
                    raise ValueError('COL allocation truncated during read')
                at = 0
                while at < len(data):
                    # IMG sector padding is permitted only after full records.
                    if not any(data[at:]):
                        if len(data) - at >= 2048:
                            raise ValueError('Excessive COL sector padding')
                        break
                    if len(data) - at < 32 or data[at:at + 4] not in VERSIONS:
                        raise ValueError('Unsupported/truncated COL header')
                    length = struct.unpack_from('<I', data, at + 4)[0] + 8
                    if length < 72 or length > len(data) - at:
                        raise ValueError('COL record outside allocation')
                    raw_name = data[at + 8:at + 30].split(b'\0', 1)[0].decode('ascii', errors='strict')
                    name = canonical(raw_name)
                    version = VERSIONS[data[at:at + 4]]
                    model_id = struct.unpack_from('<H', data, at + 30)[0]
                    record_count += 1
                    if record_count > MAX_RECORDS:
                        raise ValueError('COL model record limit')
                    versions[str(version)] = versions.get(str(version), 0) + 1
                    if name in requested:
                        raw = data[at:at + length]
                        digest = hashlib.sha256(raw).hexdigest()
                        alias = {'archive': path.name, 'collection': collection,
                                 'collectionOffset': offset, 'recordOffset': at}
                        if digest not in assets[name]:
                            selected_bytes += length
                            if selected_bytes > MAX_SELECTED:
                                raise ValueError('Selected COL bytes limit')
                            assets[name][digest] = {'bytes': length, 'sha256': digest,
                                'crc32': binascii.crc32(raw) & 0xffffffff,
                                'version': version, 'headerModelID': model_id,
                                'headerName': raw_name, 'sources': [], '_raw': raw}
                        assets[name][digest]['sources'].append(alias)
                    at += length
        after = path.stat()
        if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
            raise ValueError('IMG archive changed during catalog generation')
    if len(loose_collections)>256:raise ValueError('Explicit COLFILE count limit')
    loose_sources = [];loose_paths=set()
    for source_path, raw_path in loose_collections:
        source_path=source_path.replace('\\','/').lower()
        if not source_path.endswith('.col') or any(canonical(p)!=p for p in source_path.split('/')):
            raise ValueError('Invalid explicit COLFILE path')
        if source_path in loose_paths:raise ValueError('Duplicate explicit COLFILE path')
        loose_paths.add(source_path)
        path=Path(raw_path).resolve();before=path.stat()
        if not path.is_file() or not 72<=before.st_size<=MAX_COLLECTION:
            raise ValueError('Explicit COLFILE byte limit')
        data=path.read_bytes();at=0;collection_count+=1
        loose_sources.append({'path':source_path,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
        while at<len(data):
            if len(data)-at<32 or data[at:at+4]not in VERSIONS:
                raise ValueError('Explicit COLFILE unsupported/truncated header')
            length=struct.unpack_from('<I',data,at+4)[0]+8
            if length<72 or length>len(data)-at:raise ValueError('Explicit COLFILE record bounds')
            raw_name=data[at+8:at+30].split(b'\0',1)[0].decode('ascii',errors='strict');name=canonical(raw_name)
            version=VERSIONS[data[at:at+4]];model_id=struct.unpack_from('<H',data,at+30)[0]
            record_count+=1
            if record_count>MAX_RECORDS:raise ValueError('COL model record limit')
            versions[str(version)]=versions.get(str(version),0)+1
            if name in requested:
                raw=data[at:at+length];digest=hashlib.sha256(raw).hexdigest()
                if digest not in assets[name]:
                    selected_bytes+=length
                    if selected_bytes>MAX_SELECTED:raise ValueError('Selected COL bytes limit')
                    assets[name][digest]={'bytes':length,'sha256':digest,'crc32':binascii.crc32(raw)&0xffffffff,
                        'version':version,'headerModelID':model_id,'headerName':raw_name,'sources':[],'_raw':raw}
                assets[name][digest]['sources'].append({'file':source_path,'collection':Path(source_path).name,
                                                      'collectionOffset':0,'recordOffset':at})
            at+=length
        after=path.stat()
        if before.st_size!=after.st_size or before.st_mtime_ns!=after.st_mtime_ns:raise ValueError('Explicit COLFILE changed')
    report = {'archives': len(sources), 'collections': collection_count,
              'records': record_count, 'versions': versions, 'selectedBytes': selected_bytes,
              'missing': sorted(name for name in requested if not assets[name]),
              'ambiguous': sorted(name for name in requested if len(assets[name]) > 1),
              'unique': sorted(name for name in requested if len(assets[name]) == 1)}
    report['explicitCOLFiles']=loose_sources
    return assets, sources, report


def ide_bindings(stock_models):
    path = Path(stock_models)
    if not path.is_file() or path.stat().st_size > 16 * 1024**2:
        raise ValueError('Stock IDE manifest byte limit')
    manifest = json.loads(path.read_text())
    if manifest.get('schema') != 1 or len(manifest.get('models', [])) > 30_000:
        raise ValueError('Stock IDE manifest schema/count')
    sources = {row['path'].lower(): row for row in manifest.get('sources', [])}
    bindings = {}
    for row in manifest['models']:
        source = sources.get(row['source'].lower())
        if not source or not re.fullmatch('[0-9a-f]{64}', source['sha256']):
            raise ValueError('Missing exact IDE source provenance')
        bindings.setdefault(canonical(row['model']), []).append({
            'id': row['id'], 'source': row['source'], 'line': row['line'],
            'sourceSHA256': source['sha256']})
    return bindings


def generate(archives, requested, output, url_prefix='game/native/stock-collision', *, stock_models=None, bindings=None,
             loose_collections=(), stock_index=None, game_root=None):
    output = Path(output).resolve()
    if 'local-only' not in output.parts:
        raise ValueError('Original COL records/catalog must remain under local-only')
    if not url_prefix or any(canonical(p) != p for p in url_prefix.split('/')):
        raise ValueError('Invalid relative URL prefix')
    if (stock_models is None) == (bindings is None):
        raise ValueError('Provide exactly one explicit owner IDE manifest/binding map')
    bindings = ide_bindings(stock_models) if stock_models is not None else bindings
    requested = {canonical(v) for v in requested} if requested else set(bindings)
    if any(not bindings.get(name) for name in requested):
        raise ValueError('Requested name lacks explicit owner IDE provenance')
    assets, sources, report = scan(archives, requested,loose_collections)
    coverage=None
    if stock_index is not None or game_root is not None:
        if stock_models is None or stock_index is None or game_root is None:
            raise ValueError('Complete inventory requires exact stock manifest/index and game config root')
        index_path=Path(stock_index)
        if not index_path.is_file() or index_path.stat().st_size>32*1024**2:raise ValueError('Stock IMG index byte limit')
        index=json.loads(index_path.read_text())
        actual={r['archive'].lower():(r['bytes'],r['directorySHA256'])for r in sources}
        expected={r['name'].lower():(r['bytes'],r['directorySHA256'])for r in index['archives']}
        if index.get('schema')!=1 or actual!=expected:raise ValueError('COL inventory differs from the exact stock manifest IMG index')
        manifest=json.loads(Path(stock_models).read_text());config_sources={s['path'].lower():s for s in manifest['sources']}
        root=Path(game_root).resolve();files={p.relative_to(root).as_posix().lower():p for p in root.rglob('*')if p.is_file()}
        active=set()
        for key in ['data/default.dat','data/gta.dat']:
            raw=files[key].read_bytes()
            if hashlib.sha256(raw).hexdigest()!=config_sources[key]['sha256']:raise ValueError('Config provenance differs from stock manifest')
            for line in raw.decode('latin1').splitlines():
                fields=line.split('#',1)[0].strip().split()
                if fields and fields[0].upper()=='COLFILE':
                    if len(fields)!=3:raise ValueError('Invalid active COLFILE directive')
                    active.add(fields[2].replace('\\','/').lower())
        if active!={r['path']for r in report['explicitCOLFiles']}:raise ValueError('Active explicit COLFILE inventory is incomplete or contradictory')
        coverage={'complete':True,'scope':'stock-manifest-img-and-active-colfile',
                  'stockManifestSHA256':hashlib.sha256(Path(stock_models).read_bytes()).hexdigest(),
                  'archiveCount':len(sources),'explicitCOLFiles':report['explicitCOLFiles']}
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, records in sorted(assets.items()):
        values = []
        for digest, entry in sorted(records.items()):
            raw = entry.pop('_raw')
            path = output / (digest + '.col')
            if path.is_symlink():
                raise ValueError('Refusing symlink output')
            if path.exists():
                if path.read_bytes() != raw:raise ValueError('Refusing contradictory existing hash file')
            else:path.write_bytes(raw)
            entry['path'] = url_prefix + '/' + digest + '.col'
            values.append(entry)
        rows.append({'name': name, 'bindings': bindings[name], 'records': values})
    manifest = {'schema': 2, 'models': rows, 'sources': sources,'coverage':coverage}
    for filename, value in [('catalog.json', manifest), ('catalog.report.json', report)]:
        path = output / filename
        if path.is_symlink():
            raise ValueError('Refusing symlink output')
        path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    return manifest, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--img', type=Path, action='append', required=True)
    parser.add_argument('--model', action='append', default=[])
    parser.add_argument('--stock-models', type=Path, required=True)
    parser.add_argument('--stock-index',type=Path)
    parser.add_argument('--game-root',type=Path)
    parser.add_argument('--col',action='append',default=[],help='Explicit active path=owned-local-file')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--url-prefix', default='game/native/stock-collision')
    args = parser.parse_args()
    loose=[value.split('=',1)for value in args.col]
    if any(len(value)!=2 for value in loose):parser.error('--col requires relative/config/path=local-file')
    _, report = generate(args.img, args.model, args.output, args.url_prefix, stock_models=args.stock_models,
                         stock_index=args.stock_index,game_root=args.game_root,loose_collections=loose)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
