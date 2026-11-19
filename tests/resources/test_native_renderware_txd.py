#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Offline CPU TXD tests, using generated fixtures and optional owner-local TXDs.

Run: python3 tests/resources/test_native_renderware_txd.py [--no-corpus]
Requires Apple Swift and Pillow. No networking, asset downloads, renderer, or
original-game code. Source archives are opened read-only. Generated data, hashes,
build products, and reports live under local-only/research/renderware-txd.

BC pixels are compared byte-for-byte with Pillow's independently implemented
`bcn` decoder. Raw BGRA/BGRX and 565 use Pillow's raw decoder; other packed formats
use channel truth tables from Microsoft's D3DFORMAT specification. This establishes
CPU decoding parity with those oracles, not GPU rounding or in-game rendering.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import collections
import hashlib
import importlib.util
import json
import pathlib
import random
import struct
import subprocess
import sys
import time

from PIL import Image, __version__ as pillow_version

ROOT = pathlib.Path(__file__).resolve().parents[2]
VERSION = 0x1803FFFF
DXT1, DXT3, DXT5 = (int.from_bytes(code, 'little') for code in (b'DXT1', b'DXT3', b'DXT5'))


def chunk(kind, body, version=VERSION):
    return struct.pack('<III', kind, len(body), version) + body


def native(name, fmt, width, height, payloads, *, depth=None, flags=None,
           raster=None, platform=9, raster_type=4, mask='', tail=b'', extension=b''):
    compressed = fmt in (DXT1, DXT3, DXT5)
    if depth is None:
        depth = 16 if compressed or fmt in (23, 24, 25, 26, 30) else 8 if fmt in (28, 50) else 32
    if flags is None:
        flags = 9 if compressed else int(fmt not in (22, 23, 24, 30, 50))
    if raster is None:
        raster = 0x500 | (0x8000 if len(payloads) > 1 else 0)
    fields = struct.pack('<II32s32sIIHHBBBB', platform, 0x1102, name.encode('ascii'),
                         mask.encode('ascii'), raster, fmt, width, height, depth,
                         len(payloads), raster_type, flags)
    stream = fields + b''.join(struct.pack('<I', len(p)) + p for p in payloads) + tail
    return chunk(21, chunk(1, stream) + extension)


def txd(textures, *, count=None, device=2, extras=b''):
    return chunk(22, chunk(1, struct.pack('<HH', len(textures) if count is None else count, device)) + b''.join(textures) + extras)


def chunks(data, start, end):
    while start < end:
        kind, length, version = struct.unpack_from('<III', data, start)
        assert start + 12 + length <= end
        yield kind, start + 12, start + 12 + length, version
        start += 12 + length
    assert start == end


def rgba_oracle(fmt, width, height, payload):
    if fmt in (DXT1, DXT3, DXT5):
        return Image.frombytes('RGBA', (width, height), payload, 'bcn', {DXT1: 1, DXT3: 2, DXT5: 3}[fmt]).tobytes()
    if fmt == 21:
        return Image.frombytes('RGBA', (width, height), payload, 'raw', 'BGRA').tobytes()
    if fmt == 22:
        return Image.frombytes('RGB', (width, height), payload, 'raw', 'BGRX').convert('RGBA').tobytes()
    if fmt == 23:
        return Image.frombytes('RGB', (width, height), payload, 'raw', 'BGR;16').convert('RGBA').tobytes()
    if fmt == 50:
        return Image.frombytes('L', (width, height), payload).convert('RGBA').tobytes()
    if fmt == 28:
        image = Image.new('RGBA', (width, height), (255, 255, 255, 255))
        image.putalpha(Image.frombytes('L', (width, height), payload))
        return image.tobytes()
    # Tables make all 5-bit values explicit; the wider extrema cover alpha and
    # unused X bits independently of the production byte-swapping code.
    five = [0, 8, 16, 24, 33, 41, 49, 57, 66, 74, 82, 90, 99, 107, 115, 123,
            132, 140, 148, 156, 165, 173, 181, 189, 198, 206, 214, 222, 231, 239, 247, 255]
    four = [0, 17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204, 221, 238, 255]
    result = bytearray()
    for (value,) in struct.iter_unpack('<H', payload):
        if fmt in (24, 25):
            result.extend((five[(value >> 10) & 31], five[(value >> 5) & 31], five[value & 31],
                           255 if fmt == 24 or value >= 32768 else 0))
        elif fmt in (26, 30):
            result.extend((four[(value >> 8) & 15], four[(value >> 4) & 15], four[value & 15],
                           255 if fmt == 30 else four[value >> 12]))
        else:
            raise AssertionError(fmt)
    return bytes(result)


def expected(data):
    root, = chunks(data, 0, len(data))
    children = list(chunks(data, root[1], root[2]))
    info = next(c for c in children if c[0] == 1)
    count, device = struct.unpack_from('<HH', data, info[1])
    result, decoded = [], 0
    for entry in children:
        if entry[0] != 21:
            continue
        info = next(c for c in chunks(data, entry[1], entry[2]) if c[0] == 1)
        at = info[1]
        platform, filtering, name, mask, raster, fmt, width, height, depth, mip_count, raster_type, flags = struct.unpack_from('<II32s32sIIHHBBBB', data, at)
        name = name.split(b'\0')[0].decode('ascii')
        mask = mask.split(b'\0')[0].decode('ascii')
        mips, offset = [], at + 88
        for level in range(mip_count):
            size, = struct.unpack_from('<I', data, offset)
            offset += 4
            w, h = max(1, width >> level), max(1, height >> level)
            pixels = rgba_oracle(fmt, w, h, data[offset:offset + size]) if size else None
            mips.append({'width': w, 'height': h, 'rowBytes': w * 4, 'encodedByteCount': size,
                         'sha256': hashlib.sha256(pixels).hexdigest() if pixels is not None else None,
                         'transparent': pixels is not None and any(a != 255 for a in pixels[3::4])})
            offset += size
            decoded += len(pixels) if pixels is not None else 0
        assert offset == info[2]
        result.append({'name': name, 'lookupName': name.lower(), 'maskName': mask,
                       'filterAddressing': filtering, 'rasterFormat': raster, 'd3dFormat': fmt,
                       'depth': depth, 'nativeFlags': flags, 'declaresAlpha': bool(flags & 1),
                       'automaticMipmaps': bool(flags & 4), 'transparent': any(m['transparent'] for m in mips), 'mips': mips})
    assert count == len(result)
    return {'version': root[3], 'deviceID': device, 'decodedBytes': decoded, 'textures': result}


def rectangular_tail_cases(add):
    # Authored BC block arithmetic. Rectangular stored mips still occupy whole
    # blocks; an omitted trailing record keeps no RGBA bytes at all. The real
    # header evidence includes 4x2, 4x1 and 8x2; long strips test the explicit
    # one-small-axis policy without claiming those shapes occurred in that set.
    for fmt, block_bytes in ((DXT1, 8), (DXT3, 16), (DXT5, 16)):
        for width, height, first_missing in ((8,4,1),(4,8,1),(16,4,1),(4,16,1),
                                             (16,2,1),(2,16,1),(32,2,1),(2,32,1),
                                             (128,64,5),(64,128,5)):
            levels=max(width,height).bit_length()
            payloads=[bytes(((max(1,width>>level)+3)//4)*((max(1,height>>level)+3)//4)*block_bytes)
                      if level<first_missing else b'' for level in range(levels)]
            body=txd([native('rectangle',fmt,width,height,payloads)])
            golden=expected(body);mips=golden['textures'][0]['mips']
            assert all(m['sha256']is not None for m in mips[:first_missing])
            assert all(m['sha256']is None and m['encodedByteCount']==0 for m in mips[first_missing:])
            assert golden['decodedBytes']==sum(max(1,width>>level)*max(1,height>>level)*4 for level in range(first_missing))
            add(f'omitted-rectangle-{fmt:x}-{width}x{height}',body)
        add(f'empty-bc-base-rectangle-{fmt:x}',txd([native('bad',fmt,2,8,[b''])]),'malformed')
        add(f'empty-bc-nontail-square-{fmt:x}',txd([native('bad',fmt,8,8,[bytes(4*block_bytes),b''])]),'malformed')
        add(f'empty-bc-nontail-rectangle-{fmt:x}',txd([native('bad',fmt,16,8,[bytes(8*block_bytes),b''])]),'malformed')
        add(f'empty-bc-resumed-rectangle-{fmt:x}',txd([native('bad',fmt,8,4,[bytes(2*block_bytes),b'',bytes(block_bytes)])]),'malformed')
        add(f'empty-bc-resumed-long-{fmt:x}',txd([native('bad',fmt,16,4,[bytes(4*block_bytes),b'',bytes(block_bytes)])]),'malformed')
    for fmt in (21,22):
        add(f'empty-raw-rectangle-tail-{fmt}',txd([native('bad',fmt,8,4,[bytes(8*4*4),b''])]),'malformed')
        add(f'empty-raw-rectangle-base-{fmt}',txd([native('bad',fmt,2,8,[b''])]),'malformed')



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-corpus', action='store_true', help='test only generated data')
    parser.add_argument('--corpus', type=pathlib.Path, default=ROOT / 'local-only/site/game')
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'local-only/research/renderware-txd')
    parser.add_argument('--module-cache', type=pathlib.Path, help='reuse a writable Swift SDK module cache')
    args = parser.parse_args()
    output = args.output.resolve()
    # Avoid accidentally placing derivative images/build products in the archive.
    allowed = (ROOT / 'local-only/research').resolve()
    if allowed not in output.parents:
        parser.error('--output must be inside this workspace local-only/research')
    output.mkdir(parents=True, exist_ok=True)
    generated = output / 'generated'
    generated.mkdir(exist_ok=True)
    cases, coverage = [], collections.Counter()
    started = time.monotonic()

    def add(label, data, error=None, limits=None):
        path = generated / (label + '.txd')
        path.write_bytes(data)
        case = {'label': label, 'path': str(path)}
        if error:
            case['error'] = error
        else:
            case['expected'] = expected(data)
        if limits:
            case['limits'] = limits
        cases.append(case)

    randomizer = random.Random(0x5A4D50)
    color_indices = sum((n % 4) << (2 * n) for n in range(16))
    # Hand-verifiable red/blue colors and alpha coverage, including reversed/equal
    # endpoints that must stay four-color in BC2/BC3 but become transparent in BC1.
    for fmt in (DXT1, DXT3, DXT5):
        for order, (first, second) in enumerate(((0xF800, 0x001F), (0x001F, 0xF800), (0xF800, 0xF800))):
            color = struct.pack('<HHI', first, second, color_indices)
            for alpha_mode in range(2 if fmt == DXT5 else 1):
                if fmt == DXT1:
                    payload = color
                elif fmt == DXT3:
                    payload = bytes.fromhex('1032547698badcfe') + color
                else:
                    a0, a1 = (255, 0) if alpha_mode == 0 else (0, 255)
                    indices = sum((n % 8) << (3 * n) for n in range(16))
                    payload = bytes((a0, a1)) + indices.to_bytes(6, 'little') + color
                add(f'bc-edges-{fmt:x}-{order}-{alpha_mode}', txd([native('BC_edges', fmt, 4, 4, [payload], mask='mask')]))
        # Random valid encoded blocks compare every output channel, including
        # clipped edge blocks and small final mip sizes. All bytes are generated.
        for case in range(96):
            width, height = randomizer.choice((1, 2, 3, 4, 5, 7, 8, 12, 15)), randomizer.choice((1, 2, 3, 4, 5, 7, 8, 12, 15))
            block_size = 8 if fmt == DXT1 else 16
            payload = bytes(randomizer.randrange(256) for _ in range(((width + 3) // 4) * ((height + 3) // 4) * block_size))
            add(f'bc-random-{fmt:x}-{case:03}', txd([native('random', fmt, width, height, [payload])]))

    for fmt in (21, 22, 23, 24, 25, 26, 30, 28, 50):
        depth = 32 if fmt in (21, 22) else 8 if fmt in (28, 50) else 16
        # Exhaustive 16-bit words exercise every packed alpha/RGB combination.
        payload = (b''.join(struct.pack('<H', v) for v in range(65536)) if depth == 16
                   else bytes(range(256)) * (depth // 8))
        width, height = (256, 256) if depth == 16 else (16, 16)
        add(f'raw-{fmt}', txd([native('raw', fmt, width, height, [payload], mask='RAW_mask')]))
    add('empty-dictionary', txd([]))
    add('device-unspecified', txd([], device=0))
    add('unknown-chunks-skipped', txd([native('full_32_byte_name_abcdefghijklmno', DXT1, 4, 4, [bytes(8)], extension=chunk(3, b'opaque extension'))], extras=chunk(0xDEAD, b'unknown chunk')))
    add('mip-chain', txd([native('mips', DXT1, 8, 4, [bytes(16), bytes(8), bytes(8), bytes(8)])]))
    add('omitted-tiny-tail', txd([native('mips', DXT1, 8, 8, [bytes(32), bytes(8), b'', b''])]))

    rectangular_tail_cases(add)

    good_native = native('valid', DXT1, 4, 4, [bytes(8)])
    good = txd([good_native])
    # Every incomplete prefix of a valid nested file must fail without trapping.
    for end in range(len(good)):
        add(f'truncated-{end:03}', good[:end], 'malformed')
    add('wrong-root', chunk(0x10, b''), 'malformed')
    add('second-root', good + good, 'malformed')
    add('extra-trailing-byte', good + b'\0', 'malformed')
    add('root-huge-length', good[:4] + struct.pack('<I', 0xFFFFFFFF) + good[8:], 'malformed')
    add('native-huge-length', txd([good_native[:4] + struct.pack('<I', 0xFFFFFFFF) + good_native[8:]]), 'malformed')
    add('mismatched-count', txd([good_native], count=2), 'malformed')
    add('duplicate-casefold-name', txd([good_native, native('VALID', DXT1, 4, 4, [bytes(8)])]), 'malformed')
    add('duplicate-dictionary-struct', txd([good_native], extras=chunk(1, bytes(4))), 'malformed')
    add('native-without-struct', txd([chunk(21, chunk(3, b''))]), 'malformed')
    add('native-two-structs', txd([chunk(21, good_native[12:] * 2)]), 'malformed')
    add('bad-mip-length', txd([native('bad', DXT1, 4, 4, [bytes(7)])]), 'malformed')
    add('trailing-native-bytes', txd([native('bad', DXT1, 4, 4, [bytes(8)], tail=b'\0')]), 'malformed')
    add('zero-base-mip', txd([native('bad', DXT1, 4, 4, [b''])]), 'malformed')
    add('empty-big-mip', txd([native('bad', DXT1, 8, 8, [bytes(32), b''])]), 'malformed')
    add('nonempty-after-empty', txd([native('bad', DXT1, 8, 8, [bytes(32), bytes(8), b'', bytes(8)])]), 'malformed')
    add('no-mips', txd([native('bad', DXT1, 4, 4, [])]), 'malformed')
    add('too-many-mips', txd([native('bad', DXT1, 4, 4, [bytes(8)] * 4)]), 'malformed')
    add('no-mipmap-flag', txd([native('bad', DXT1, 4, 4, [bytes(8)] * 2, raster=0x200)]), 'malformed')
    add('zero-width', txd([native('bad', DXT1, 0, 4, [bytes(8)])]), 'malformed')
    add('zero-height', txd([native('bad', DXT1, 4, 0, [bytes(8)])]), 'malformed')
    add('raw-depth', txd([native('bad', 21, 1, 1, [bytes(4)], depth=16)]), 'malformed')
    add('compression-flag', txd([native('bad', DXT1, 4, 4, [bytes(8)], flags=1)]), 'malformed')
    add('raw-compression-flag', txd([native('bad', 21, 1, 1, [bytes(4)], flags=9)]), 'malformed')
    for label, keywords in (
            ('platform', {'platform': 8}), ('cube', {'flags': 11}),
            ('palette4', {'raster': 0x4000}), ('palette8', {'raster': 0x2000}),
            ('raster-type', {'raster_type': 5}), ('unknown-flags', {'flags': 0x89}),
            ('compressed-depth', {'depth': 4})):
        add(label, txd([native('unsupported', DXT1, 4, 4, [bytes(8)], **keywords)]), 'unsupported')
    add('unsupported-dxt2', txd([native('bad', int.from_bytes(b'DXT2', 'little'), 4, 4, [bytes(16)])]), 'unsupported')
    add('unsupported-device', txd([good_native], device=3), 'unsupported')
    add('path-name', txd([native('../file', DXT1, 4, 4, [bytes(8)])]), 'unsupported')
    add('empty-name', txd([native('', DXT1, 4, 4, [bytes(8)])]), 'malformed')
    for label, limit in (
            ('encoded-budget', {'fileBytes': len(good) - 1}),
            ('dimension-budget', {'dimension': 3}), ('decoded-budget', {'decodedBytes': 63}),
            ('chunk-budget', {'chunkCount': 3}), ('invalid-limit', {'dimension': 65536})):
        add(label, good, 'limitExceeded', limit)
    add('texture-count-budget', txd([good_native, native('second', DXT1, 4, 4, [bytes(8)])]), 'limitExceeded', {'textureCount': 1})
    add('mip-budget', txd([native('mips', DXT1, 4, 4, [bytes(8)] * 2)]), 'limitExceeded', {'mipLevels': 1})
    add('cumulative-budget', txd([good_native, native('second', DXT1, 4, 4, [bytes(8)])]), 'limitExceeded', {'decodedBytes': 127})

    corpus_hashes, helper_matches = {}, 0
    if not args.no_corpus:
        paths = sorted(args.corpus.glob('*.txd'))
        if not paths:
            raise SystemExit('No owner-local TXDs found; use --no-corpus for generated-only tests')
        specification = importlib.util.spec_from_file_location('local_prepare_native_models', ROOT / 'tools/assets/prepare_native_models.py')
        helper = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(helper)
        for path in paths:
            data = path.read_bytes()
            corpus_hashes[str(path.resolve())] = hashlib.sha256(data).hexdigest()
            golden = expected(data)
            previous = helper.textures(path)
            for texture in golden['textures']:
                coverage[str(texture['d3dFormat'])] += 1
                base = texture['mips'][0]
                assert texture['lookupName'] in previous, (path.name, texture['name'])
                assert hashlib.sha256(previous[texture['lookupName']].tobytes()).hexdigest() == base['sha256'], (path.name, texture['name'])
                helper_matches += 1
            cases.append({'label': 'owner-local/' + path.name, 'path': str(path.resolve()), 'expected': golden})
    manifest = output / 'manifest.json'
    manifest.write_text(json.dumps(cases, separators=(',', ':')))
    cache = args.module_cache.resolve() if args.module_cache else output / 'module-cache'
    cache.mkdir(exist_ok=True)
    binary = output / 'txd-tests'
    command = ['xcrun', 'swiftc', '-O', '-module-cache-path', str(cache),
               str(ROOT / 'ios/App/NativeRenderWareTXD.swift'), str(ROOT / 'tests/renderware_txd/main.swift'), '-o', str(binary)]
    subprocess.run(command, check=True, cwd=ROOT)
    completed = subprocess.run([str(binary), str(manifest)], cwd=ROOT, text=True, capture_output=True)
    (output / 'swift.stdout').write_text(completed.stdout)
    (output / 'swift.stderr').write_text(completed.stderr)
    if completed.returncode:
        print(completed.stdout, end='')
        print(completed.stderr, end='', file=sys.stderr)
        raise SystemExit(completed.returncode)
    for path, sha in corpus_hashes.items():
        assert hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest() == sha, 'owner-local source changed'
    summary = json.loads(completed.stdout)
    summary.update({'ownerLocalFiles': len(corpus_hashes), 'ownerLocalBaseMipsMatchedExistingConverter': helper_matches,
                    'ownerLocalFormats': dict(coverage), 'pillowVersion': pillow_version,
                    'sourceArchivesUnchanged': True, 'elapsedSeconds': round(time.monotonic() - started, 3),
                    'scope': 'CPU decoding only; no Metal integration or rendered custom-model claim'})
    (output / 'report.json').write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
