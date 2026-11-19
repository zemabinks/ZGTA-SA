#!/usr/bin/env python3
"""Extract public water wave regions, components, and weather coefficients."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import ast
import hashlib
import json
import re
from pathlib import Path
from tools.assets.prepare_native_atmosphere import ROOT, array


def numeric_array(source, name):
    begin = re.search(r'\b' + name + r'=\[', source).end()-1
    depth = 0
    for end in range(begin, len(source)):
        depth += (source[end] == '[') - (source[end] == ']')
        if depth == 0:
            text = re.sub(r'(?<=[\[,])\s*(-?)\.(\d)', r'\g<1>0.\2', source[begin:end+1])
            node = ast.parse(text, mode='eval').body
            def number(n):
                if isinstance(n, ast.List): return [number(i) for i in n.elts]
                if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)): return n.value
                if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.USub): return -number(n.operand)
                if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Div): return number(n.left)/number(n.right)
                raise ValueError('Non-numeric expression')
            return number(node)
    raise ValueError('Unclosed array')


def main():
    chunks = ROOT / 'local-only/site/_next/static/chunks'
    wave_file = next(p for p in chunks.glob('*.js') if '9527:(e,t,l)' in p.read_text())
    render_file = next(p for p in chunks.glob('*.js') if '45065:(e,t,a)' in p.read_text())
    wave = wave_file.read_text().split('9527:(e,t,l)',1)[1].split('35409:e=>',1)[0]
    render = render_file.read_text().split('45065:(e,t,a)',1)[1].split('87719:',1)[0]
    encoded = re.search(r'\bn=JSON.parse\(("(?:\\.|[^"\\])*")\)', wave).group(1)
    regions = json.loads(json.loads(encoded))
    result = {'source': {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [wave_file,render_file]},
              'regions':regions,'xFactors':array(wave,'a'),'yFactors':array(wave,'i'),
              'wind':array(render,'o'),'components':numeric_array(render,'s')}
    assert all(len(r)==12 and r[0]<r[2] and r[1]<r[3] for r in regions)
    output=ROOT/'local-only/site/game/native/water-waves.json'
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,separators=(',',':'))+'\n');output.chmod(0o600)
    print(f'Prepared {len(regions)} water wave regions in {output}')


if __name__=='__main__':main()
