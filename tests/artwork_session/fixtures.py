# SPDX-License-Identifier: AGPL-3.0-only
"""Independently generated, textured PC RW fixtures; no original game bytes."""
import struct


def p(fmt, *values):
    return struct.pack('<' + fmt, *values)


def chunk(kind, data=b''):
    return p('III', kind, len(data), 0x1803ffff) + data


def assets():
    frame = chunk(14, chunk(1, p('I12fiI', 1, 1,0,0,0,1,0,0,0,1,0,0,0,-1,0)) + chunk(3))
    texture = chunk(6, chunk(1, p('I',0x1101)) + chunk(2,b'session_texture\0') + chunk(2,b'\0') + chunk(3))
    material = chunk(7, chunk(1,p('I4BII3f',0,255,255,255,255,0,1,1,1,1)) + texture + chunk(3))
    materials = chunk(8,chunk(1,p('Ii',1,-1)) + material)
    geometry = p('HBBIII',0x16,1,0,1,3,1) + p('6f',0,0,1,0,0,1) + p('4H',1,0,0,2)
    geometry += p('4fII',0,0,0,2,1,1) + p('9f',0,0,0,1,0,0,0,0,1) + p('9f',0,1,0,0,1,0,0,1,0)
    geometries = chunk(26,chunk(1,p('I',1)) + chunk(15,chunk(1,geometry) + materials + chunk(3)))
    atomic = chunk(20,chunk(1,p('4I',0,0,5,0)) + chunk(3))
    dff = chunk(16,chunk(1,p('3I',1,0,0)) + frame + geometries + atomic + chunk(3))
    bgra = bytes([0,0,255,255,0,255,0,255,255,0,0,255,255,255,255,255])
    fields = p('II32s32sIIHHBBBB',9,0x1101,b'session_texture',b'',0x500,21,2,2,32,1,4,1)
    txd = chunk(22,chunk(1,p('HH',1,2)) + chunk(21,chunk(1,fields+p('I',len(bgra))+bgra)+chunk(3)) + chunk(3))
    return dff,txd
