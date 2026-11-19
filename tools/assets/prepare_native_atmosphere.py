#!/usr/bin/env python3
"""Prepare the archived client's sky tables and deterministic cloud geometry.

All extracted game data remains in local-only; this source contains only the
extraction and the browser's publicly delivered geometry construction rules.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib
import json
import re
import struct
from pathlib import Path
from tools.assets.prepare_native_audio import json_module

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'local-only/site/game/native/atmosphere.json'


def array(source, name):
    match = re.search(r'\b' + re.escape(name) + r'=(\[)', source)
    assert match, name
    begin = match.start(1)
    depth = 0
    for end in range(begin, len(source)):
        depth += (source[end] == '[') - (source[end] == ']')
        if depth == 0:
            text = source[begin:end + 1]
            # These arrays consist exclusively of numeric literals.
            assert re.fullmatch(r'[\[\]\s,.\deE+\-]+', text)
            text = re.sub(r'(?<=[\[,])\s*(-?)\.(\d)', r'\g<1>0.\2', text)
            return json.loads(text)
    raise ValueError(f'Unclosed array {name}')


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def main():
    chunk = next(p for p in (ROOT / 'local-only/site/_next/static/chunks').glob('*.js')
                 if 'yM=[...wD.c$,24]' in p.read_text())
    source = chunk.read_text()
    table = json.loads(re.search(r"\bwD=JSON.parse\('(.+?)'\)", source).group(1))
    weather, weather_path = json_module(93265)
    constants = {name: array(source, name) for name in
                 ['wW', 'wH', 'wG', 'wV', 'wY', 'w$', 'wJ', 'wQ',
                  'yS', 'y_', 'yN', 'yz', 'yT', 'yC', 'yE', 'yR', 'yO']}
    r = constants['wW']
    at = lambda index: r[index % len(r)]
    import math
    projection = 2 * math.tan(35 * math.pi / 180)
    sheets = []
    for i in range(1, 29):
        sheets.append({'spot': list(map(f32, [512*at(i-1), 512*at(i), .5*at(i+5)+1, at(i+1)])),
                       'span': list(map(f32, [100*at(i+2)+60, 100*at(i+3)+60, 0]))})
    for i in range(30):
        sheets.append({'spot': list(map(f32, [constants['wH'][i], constants['wG'][i], .5, at(i)])),
                       'span': list(map(f32, [(at(i+1)+1)*12*projection, 0, 1]))})
    seed = 23057
    def random(lo, hi):
        nonlocal seed
        seed = (seed * 1664525 + 0x3c6ef35f) & 0xffffffff
        return lo + seed / 0x100000000 * (hi - lo)
    high = []
    for group in range(36):
        scale = random(1, 5)
        home = [random(-v, v) for v in constants['wV']]
        for item in range(5):
            for axis in range(3):
                home[axis] += random(-3*scale, 3*scale)
            girth = [random(20*scale, 100*scale), random(20*scale, 40*scale), random(20*scale, 100*scale)]
            high.append({'home': list(map(f32, home)), 'girth': list(map(f32, girth)),
                         'density': f32(math.floor(random(36, 128))/255)})
    assert len(table['Ge']) == 23 and all(len(w) == 8 and all(len(row) == 21 for row in w) for w in table['Ge'])
    result = {'source': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [chunk, weather_path]},
              'hours': table['c$'], 'colors': table['Ge'], 'wind': weather['LO'],
              'gusts': weather['ZL'], 'directions': weather['Li'],
              'constants': constants, 'sheets': sheets, 'highClouds': high}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(result, separators=(',', ':')) + '\n')
    OUTPUT.chmod(0o600)
    print(f'Prepared {len(sheets)} cloud sheets and {len(high)} cloud volumes in {OUTPUT}')


if __name__ == '__main__':
    main()
