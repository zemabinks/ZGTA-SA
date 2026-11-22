#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""An invented triangle and two-bone family. No original game resources."""
import base64
import json
import struct
import zlib


def family():
    points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
    mesh = (struct.pack('<4I', 0x324c5257, 3, 3, 1) +
            b''.join(struct.pack('<3f', *p) for p in points) +
            struct.pack('<6f', 0, 0, 1, 0, 0, 1) + struct.pack('<3I', 0, 1, 2) +
            bytes([255] * 12) + bytes(6) + bytes(2) + bytes([255] * 12) + bytes(2))
    matrix = struct.pack('<16f', *[float(i % 5 == 0) for i in range(16)])
    skeleton = struct.pack('<4I', 0x314e4b53, 3, 2, 2) + matrix * 2
    skeleton += struct.pack('<2i', -1, 0) + matrix + struct.pack('<2i', 0, 1) + matrix
    skeleton += struct.pack('<I', 0) + matrix + struct.pack('<I', 1) + matrix
    skeleton += b''.join(struct.pack('<3f4B4f', *p, 0, 0, 0, 0, 1, 0, 0, 0) for p in points)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    atlas = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>2I5B', 1024, 128, 8, 6, 0, 0, 0)) +
             chunk(b'IDAT', zlib.compress((b'\0' + bytes([255]) * 4096) * 128)) + chunk(b'IEND', b''))
    return mesh, atlas, skeleton


if __name__ == '__main__':
    print(json.dumps([base64.b64encode(b).decode() for b in family()]))
