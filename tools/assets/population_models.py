"""Structural admission for a prepared pedestrian mesh, atlas and skeleton.

This is a source-family gate, not a GPU decode, bind-pose or animation test.
"""
# SPDX-License-Identifier: AGPL-3.0-only
import math
import struct


def validate_family(mesh, atlas, skeleton):
    def require(value, why):
        if not value:
            raise ValueError('Population model ' + why)

    def floats(data, begin, count):
        values = struct.unpack_from('<' + 'f' * count, data, begin)
        require(all(math.isfinite(v) for v in values), 'nonfinite geometry/rig')
        return values

    require(len(mesh) >= 16 and len(mesh) <= 64 * 1024 * 1024, 'mesh byte budget')
    magic, vertices, indices, layers = struct.unpack_from('<4I', mesh)
    require(magic == 0x324c5257 and 0 < vertices < 100000 and 0 < indices <= 3000000 and
            indices % 3 == 0 and 0 < layers <= 65535, 'mesh header')
    require(len(mesh) == 16 + 30 * vertices + 4 * indices + 2 * (vertices % 2) + 2 * layers,
            'mesh exact length')
    floats(mesh, 16, vertices * 5)
    require(all(v[0] < vertices for v in struct.iter_unpack('<I', mesh[16 + vertices * 20:
                16 + vertices * 20 + indices * 4])), 'mesh triangle index')
    layer_at = 16 + vertices * 24 + indices * 4
    require(all(v[0] < layers for v in struct.iter_unpack('<H', mesh[layer_at:layer_at + vertices * 2])),
            'mesh texture layer')
    require(33 <= len(atlas) <= 64 * 1024 * 1024 and atlas[:8] == b'\x89PNG\r\n\x1a\n' and
            atlas[8:16] == b'\0\0\0\rIHDR', 'atlas header')
    width, height = struct.unpack_from('>2I', atlas, 16)
    require(0 < width <= 16384 and 0 < height <= 16384 and width * height <= 67108864,
            'atlas dimensions')
    require(len(skeleton) >= 144 and len(skeleton) <= 64 * 1024 * 1024, 'skeleton byte budget')
    magic, count, frames, bones = struct.unpack_from('<4I', skeleton)
    require(magic == 0x314e4b53 and count == vertices and 0 < frames <= 512 and 0 < bones <= 64,
            'mesh/skeleton header identity')
    require(len(skeleton) == 144 + frames * 72 + bones * 68 + vertices * 32, 'skeleton exact length')
    floats(skeleton, 16, 32)
    tags = set()
    at = 144
    for index in range(frames):
        parent, tag = struct.unpack_from('<2i', skeleton, at)
        require(-1 <= parent < index and tag >= -1 and (tag < 0 or tag not in tags), 'frame hierarchy/tag')
        if tag >= 0:
            tags.add(tag)
        floats(skeleton, at + 8, 16)
        at += 72
    require({0, 1}.issubset(tags), 'required actor bone tags')
    for _ in range(bones):
        require(struct.unpack_from('<I', skeleton, at)[0] < frames, 'palette frame')
        floats(skeleton, at + 4, 16)
        at += 68
    for _ in range(vertices):
        floats(skeleton, at, 3)
        require(max(skeleton[at + 12:at + 16]) < bones, 'skin palette index')
        weights = floats(skeleton, at + 16, 4)
        require(min(weights) >= 0 and abs(sum(weights) - 1) < .01, 'skin weights')
        at += 32
    return dict(vertices=vertices, indices=indices, layers=layers, frames=frames, bones=bones,
                atlas=[width, height])
